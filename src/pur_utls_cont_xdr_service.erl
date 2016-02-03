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

-module(pur_utls_cont_xdr_service).

-behavior(pur_utls_pipe_server).

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2, handle_pipe/2,
         terminate/2, code_change/3,
         parse_header_for_payload_size/2, 
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_xdr.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

-record(state, {socket, 
                header_size,
                xdr_codecs,
                xdr_args,
                service_pipe,
                % Not really used
                recv_server,
                server_ref = make_ref()}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions =
        [fun (_NProps, _Context, State) ->
             {true, State#state{xdr_codecs = pur_utls_xdr:build_codecs()}}
         end,
         fun start_recv_server/3],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "socket",
                   index = #state.socket,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "header_size", 
                   index = #state.header_size,
                   ret_type = integer,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "xdr_args", 
                   index = #state.xdr_args,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "service_pipe", 
                   index = #state.service_pipe,
                   directive = required,
                   dirvalue = true}],
        InitFunctions,
        [],
        #state{}).

terminate(Reason, State) ->
    CState = close(State),
    case Reason of
        normal -> ok;
        shutdown -> ok;
        {shutdown, _} -> ok;
        Reason -> ?LogIt(terminate,
                         "Terminated for reason: ~n~p, ~nwith state:~n~p.",
                         [Reason, CState])
    end.

code_change(_, State, _) -> 
    {ok, State}.

%%----------------------------------------------------------------------------
%% Genserver Exported Behavior
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% handle_call
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% Unknown call expression
%%----------------------------------------------------------------------------

handle_call(Expr, _From, State) ->
    ?LogIt({handle_call, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {reply, ok, State}.

%%----------------------------------------------------------------------------
%% handle_cast
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% change_xdr_args
%%----------------------------------------------------------------------------

handle_cast({change_xdr_args, Args}, State) ->
    {noreply, State#state{xdr_args = Args}};

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

handle_cast(close, State) ->
    NState = close(State),
    % Should not return. May have to use kill versus normal.
    exit(normal),
    {noreply, NState};

%%----------------------------------------------------------------------------
%% exit_service
%%----------------------------------------------------------------------------

handle_cast({exit_service, _Ref}, State) ->
    CState = close(State),
    exit(normal),
    {noreply, CState};

%%----------------------------------------------------------------------------
%% Unknown cast expression
%%----------------------------------------------------------------------------

handle_cast(Expr, State) ->
    ?LogIt({handle_cast, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {noreply, State}.

%%----------------------------------------------------------------------------
%% handle_info
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% Unknown info expression
%%----------------------------------------------------------------------------

handle_info(Expr, State) ->
    ?LogIt({handle_info, unknown}, "Unknown expr: ~n~p. ~nIgnoring", [Expr]),
    {noreply, State}.

%%----------------------------------------------------------------------------
%% handle_pipe
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% handle_received_payload pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             handle_received_payload, 
             {Length, Payload}}, 
            State) ->
    {Result, RState} = handle_received_payload(Length, Payload, State),
    {reply, Result, SessionId, RState};

%%----------------------------------------------------------------------------
%% Unknown pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, _Term, Expr}, State) ->
    % Skips to next in pipe
    {reply, Expr, SessionId, State}.

%%----------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% "Spawn" Behavior
%%----------------------------------------------------------------------------

spawn(nolink, Name = {global, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, Name, NStartArgs, StartOptions);
spawn(nolink, Name = {local, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, Name, NStartArgs, StartOptions);
spawn(link, Name = {global, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, Name, NStartArgs, StartOptions);
spawn(link, Name = {local, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, Name, NStartArgs, StartOptions).

spawn(nolink, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, NStartArgs, StartOptions);
spawn(link, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, ?MODULE}|StartArgs],
    pur_utls_pipe_server:spawn(link, NStartArgs, StartOptions).

%%----------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% start_recv_server
%%----------------------------------------------------------------------------

start_recv_server(_Props, 
                  _Context, 
                  State = #state{socket = Socket, 
                                 header_size = HeaderSize,
                                 service_pipe = Pipe}) ->
    PipeComp = #pipecomp{name = "process_payload", 
                         pipe_name = "payload_receiver",
                         type = cast,
                         exec = handle_received_payload,
                         to = self()},
    Args = [{socket, Socket}, 
            {service_pipe, [PipeComp|Pipe]}, 
            {service_session_id, "payload_session"},
            {header_size, HeaderSize},
            {header_handler, fun ?MODULE:parse_header_for_payload_size/2},
            {header_handler_context, HeaderSize bsl 3}],
    case pur_utls_recv_slave:spawn(link, Args, []) of
        {ok, Pid} ->
            {true, State#state{recv_server = Pid}};
        Reason ->
            {false, Reason, State}
    end.

%%----------------------------------------------------------------------------
%% parse_header_for_payload_size
%%----------------------------------------------------------------------------

% Not a gen_server function (no state), just a POF
parse_header_for_payload_size(BLength, NumBits) 
        when is_bitstring(BLength), bit_size(BLength) == NumBits ->
    <<Length:NumBits>> = BLength,
    {ok, Length};
parse_header_for_payload_size(Header, _) ->
    Reason = 
        ?LogItMessage(parse_header_for_payload_size,
                      "Bad header: ~p, received.",
                      [Header]),
    ?LogItRaw(Reason),
    {error, Reason}.

%%----------------------------------------------------------------------------
%% exit_service
%%----------------------------------------------------------------------------

-ifdef(Unused).
exit_service(State = #state{server_ref = Ref}) ->
    gen_server:cast(self(), {exit_service, Ref}),
    State.
-endif.

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

close(State = #state{socket = undefined, recv_server = undefined}) ->
    State;
close(State = #state{socket = undefined, recv_server = Server}) ->
    gen_server:cast(Server, close),
    State#state{recv_server = undefined};
close(State = #state{socket = Socket, recv_server = undefined}) ->
    gen_tcp:shutdown(Socket, read),
    gen_tcp:close(Socket),
    State#state{socket = undefined};
close(State = #state{recv_server = Server}) ->
    gen_server:cast(Server, close),
    close(State#state{recv_server = undefined}).

%%----------------------------------------------------------------------------
%% handle_received_payload
%%----------------------------------------------------------------------------

handle_received_payload(_Length,
                        Payload,
                        State = #state{xdr_codecs = Codecs,
                                       xdr_args = XdrCallArgs}) ->
    CallArgs = XdrCallArgs#call_args{codec_env = Codecs},
    Decoded = pur_utls_xdr:decode_generic(Payload, CallArgs),
    {Decoded, State}.

