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

-module(pur_utls_fun_pipe_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").

-export([response_call_fun/4, response_cast_fun/3, response_pipe_fun/2,
         operation/2, delay_send/2]).

-record(delay_state, {delay_with = 0}).
-record(operation_state, {operator, result = 0}).
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

operation({#pipe_context{}, calculate, Arg},
          State = #operation_state{operator = Op, result = LastResult}) ->
    Result =
        case Op of
            add -> 
                Arg + LastResult;
            multiply -> 
                Arg * LastResult;
            divide -> 
                LastResult / Arg;
            Unknown -> 
                ?LogIt({operation, calculate}, 
                       "Operation: ~p, unknown.", 
                       [Unknown]),
                LastResult
        end,
    {reply, Result, State#operation_state{result = Result}}.

start_server(Type, Args, Options) ->
    case pur_utls_fun_pipe:spawn(Type, Args, Options) of
        {ok, Pid} -> 
            Pid;
        {error, {already_started, Pid}} -> 
            Pid;
        R = {error, Reason} ->
            ?LogIt(start_server, "Error with reason: ~p, received.", [Reason]),
            throw(R);
        ignore ->
            ?LogIt(start_server, "Ignore received.", []),
            throw(ignore)
    end.
    
pipe_and_wait_test() ->
    % E = fun (Expr) -> element(1, Expr) end,
    DelaySendArgs = [{pipe_module, pur_utls_fun_pipe_tests},
                     {pipe_fun, delay_send},
                     {fun_state, #delay_state{delay_with = 1000}}],
    FirstOpArgs = [{pipe_module, pur_utls_fun_pipe_tests},
                   {pipe_fun, operation},
                   {fun_state, #operation_state{operator = add}}],
    SecondOpArgs = [{pipe_module, pur_utls_fun_pipe_tests},
                    {pipe_fun, operation},
                    {fun_state, #operation_state{operator = multiply, 
                                                 result = 1}}],
    ThirdOpArgs = [{pipe_module, pur_utls_fun_pipe_tests},
                   {pipe_fun, operation},
                   {fun_state, #operation_state{operator = divide, 
                                                result = 1.0}}],
    ResponseArgs = [{pipe_module, pur_utls_fun_pipe_tests},
                    {pipe_fun, response_pipe_fun},
                    {fun_state, #response_state{}},
                    {call_module, pur_utls_fun_pipe_tests},
                    {call_fun, response_call_fun},
                    {cast_module, pur_utls_fun_pipe_tests},
                    {cast_fun, response_cast_fun}],
    DelayServer = start_server(link, DelaySendArgs, []),
    FirstOpServer = start_server(link, FirstOpArgs, []),
    SecondOpServer = start_server(link, SecondOpArgs, []),
    ThirdOpServer = start_server(link, ThirdOpArgs, []),
    RespondServer = start_server(link, ResponseArgs, []),
    Pipe = [#pipecomp{name = delay_send, 
                      type = cast, 
                      exec = send, 
                      to = DelayServer, 
                      pipe_name = main},
            #pipecomp{name = add, 
                      type = cast, 
                      exec = calculate, 
                      to = FirstOpServer, 
                      pipe_name = main},
            #pipecomp{name = multiply, 
                      type = cast, 
                      exec = calculate, 
                      to = SecondOpServer, 
                      pipe_name = main},
            #pipecomp{name = divide, 
                      type = cast, 
                      exec = calculate, 
                      to = ThirdOpServer, 
                      pipe_name = main},
            #pipecomp{name = respond, 
                      type = cast, 
                      exec = set_response, 
                      to = RespondServer, 
                      pipe_name = main}],
    pur_utls_pipes:send_to_next(5, "xxxx.1", Pipe),
    Response = gen_server:call(RespondServer, wait_for_response),
    %?LogIt(pipe_and_wait_test, "Response: ~p.", [Response]),

    gen_server:cast(RespondServer, reset_response),
    pur_utls_pipes:send_to_next(Response, "xxxx.2", Pipe),
    NextResponse = gen_server:call(RespondServer, wait_for_response),
    %?LogIt(pipe_and_wait_test, "NextResponse: ~p.", [NextResponse]),

    %lists:foreach(fun gen_server:stop/1, [DelayServer, 
    %                                      FirstOpServer, 
    %                                      SecondOpServer, 
    %                                      ThirdOpServer, 
    %                                      RespondServer]),
    ?assert(0.2 == Response),
    ?assert(0.007692307692307693 == NextResponse).

-endif.

