%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%   Copyright 2016 Purvey, Inc.
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @author: Garrison M. Venn
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(pur_utls_cont_xdr_service_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_xdr.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").

-export([response_call_fun/4, response_cast_fun/3, response_pipe_fun/2,
         delay_send/2]).

-record(delay_state, {delay_with = 0}).
-record(response_state, {waiting_for = [], response}).

response_call_fun(call, 
                  wait_for_response, 
                  From, 
                  State = #response_state{waiting_for = Waiting, 
                                          response = undefined}) ->
    {noreply, State#response_state{waiting_for = [From|Waiting]}};
response_call_fun(call, 
                  wait_for_response, 
                  From, 
                  State = #response_state{waiting_for = Waiting}) ->
    gen_server:cast(self(), broadcast_response), 
    {noreply, State#response_state{waiting_for = [From|Waiting]}}.

response_cast_fun(cast,
                  broadcast_response,
                  State = #response_state{response = undefined}) ->
    {noreply, State};
response_cast_fun(cast,
                  broadcast_response,
                  State = #response_state{waiting_for = []}) ->
    {noreply, State};
response_cast_fun(cast,
                  broadcast_response,
                  State = #response_state{waiting_for = Waiting, 
                                          response = Response}) ->
    %GDEBUG
    %?LogIt({response_cast_fun, broadcast_response}, 
    %        "response = ~n~p.", 
    %        [Response]),
    lists:foreach(
        fun (From) ->
            gen_server:reply(From, Response)
        end,
        Waiting),
    {noreply, State#response_state{waiting_for = []}};
response_cast_fun(cast,
                  reset_response,
                  State = #response_state{}) ->
    {noreply, State#response_state{response = undefined}}.

response_pipe_fun({#pipe_context{}, set_response, Response},
                   State = #response_state{}) ->
    gen_server:cast(self(), broadcast_response),
    {noreply, State#response_state{response = Response}}.

delay_send({#pipe_context{}, send, Arg},
           State = #delay_state{delay_with = Interval}) ->
    timer:sleep(Interval),
    {reply, Arg, State}.

start_server(Module, Type, Args, Options) ->
    case Module:spawn(Type, Args, Options) of
        {ok, Pid} -> 
            Pid;
        % Treating already started condition as an error
        R = {error, Reason} ->
            ?LogIt(start_server, "Error with reason: ~p, received.", [Reason]),
            throw(R);
        ignore ->
            ?LogIt(start_server, "Ignore received.", []),
            throw(ignore)
    end.

connect(Port) ->
    {ok, Socket} = gen_tcp:connect(localhost, 
                                   Port, 
                                   [binary, {packet, raw}, {active, false}]),
    Socket.

send(Data, Socket) when is_binary(Data) ->
    M = pur_utls_xdr,
    Codecs = M:build_codecs(),
    CallArgs = #call_args{codec_env = Codecs},
    NumBytes = byte_size(Data),
    NumBytesEncoded = M:encode_uint(NumBytes, CallArgs), 
    gen_tcp:send(Socket, NumBytesEncoded),
    gen_tcp:send(Socket, Data).

generate_struct_params() ->
    InnerMetaData = 
        [#call_args{etype = int},
         #call_args{etype = string},
         #call_args{etype = variable_opaque, len = 4},
         #call_args{etype = fixed_opaque, len = 3}, 
         #call_args{etype = float},
         #call_args{etype = double},
         #call_args{etype = quad},
         #call_args{etype = {fixed_array, string}, len = 2},
         #call_args{etype = {variable_array, uint}, len = 5}],
    UnionEnvData =
        #{1 => #call_args{etype = int},
          2 => #call_args{etype = string},
          3 => #call_args{etype = variable_opaque},
          4 => #call_args{etype = fixed_opaque, len = 3},
          5 => #call_args{etype = float},
          6 => #call_args{etype = double},
          7 => #call_args{etype = quad},
          8 => #call_args{etype = {fixed_array, string}, len = 2},
          9 => #call_args{etype = {variable_array, uint}},
          10 => #call_args{etype = struct, call_args = InnerMetaData}},
    %%%%%
    % Union Data
    %   [1, "one", [1, 2, 3, 4], [5, 6, 7],
    %    3.5, 4.123456789, 6789123.123456789,
    %    ["three", "four"], [8, 9, 10, 11, 12]],
    %%%%%
    OuterMetaData = 
        [#call_args{etype = string},
         #call_args{etype = union, env = UnionEnvData},
         #call_args{etype = string}],
    InnerData = [1, "one", [1, 2, 3, 4], [5, 6, 7],
                 3.5, 4.123456789, 6789123.123456789,
                 ["three", "four"], [8, 9, 10, 11, 12]],
    Codecs = pur_utls_xdr:build_codecs(),
    {#call_args{etype = struct, call_args = OuterMetaData, codec_env = Codecs},
     ["begin", {10, InnerData}, "end"],
     ["begin", InnerData, "end"]}.

xdr_send_multiple_and_wait_test() ->
    E = fun (Expr) -> element(1, Expr) end,
    Port = 10000,
    %DelaySendArgs = [{pipe_module, pur_utls_cont_xdr_service_tests},
    %                 {pipe_fun, delay_send},
    %                 {fun_state, #delay_state{delay_with = 1000}}],
    ResponseArgs = [{pipe_module, pur_utls_cont_xdr_service_tests},
                    {pipe_fun, response_pipe_fun},
                    {fun_state, #response_state{}},
                    {call_module, pur_utls_cont_xdr_service_tests},
                    {call_fun, response_call_fun},
                    {cast_module, pur_utls_cont_xdr_service_tests},
                    {cast_fun, response_cast_fun}],
    AM = pur_utls_accept_server,
    RespondServer = start_server(pur_utls_fun_pipe, link, ResponseArgs, []),
    Pipe = [#pipecomp{name = respond, 
                      type = cast, 
                      exec = set_response, 
                      to = RespondServer, 
                      pipe_name = main}],
    AcceptServer = xdr_test_accept_server,
    {CallArgs, Data, TestWith} = generate_struct_params(),
    AcceptArgs = [{port, Port}, 
                  {comm_module, pur_utls_cont_xdr_service},
                  {header_size, 4},
                  {xdr_args, CallArgs},
                  {service_pipe, Pipe}],
    AM:spawn(link, {local, AcceptServer}, AcceptArgs, []),
    gen_server:call(AcceptServer, start),
    Socket = connect(Port),
    ToSend = pur_utls_xdr:encode_generic(Data, CallArgs),
    send(ToSend, Socket),
    Response = gen_server:call(RespondServer, wait_for_response),
    % GDEBUG
    %?LogIt(xdr_send_multiple_and_wait_test, "Response: ~n~p.", [Response]),
    % Must be done first or else port binding is not released in time
    %     for next run with same port.
    gen_tcp:close(Socket),
    gen_server:stop(AcceptServer),
    gen_server:stop(RespondServer),
    ?assert(TestWith =:= E(Response)).
    %?assert(true =:= true).

-endif.

