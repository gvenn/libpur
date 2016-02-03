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

-module(pur_utls_recv_slave).

%%%%%%%%%%%%%%%%%%%
% Being a gen_server let alone a pipe server is overkill. However development
%     will proceed faster so going with it, until there is more time. REVISIT
%%%%%%%%%%%%%%%%%%%

-behavior(pur_utls_pipe_server).

% Synchronous implementation

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2, handle_pipe/2,
         terminate/2, code_change/3,
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").
-include_lib("pur_tcp_modbus.hrl").
-include_lib("pur_tcp_modbus_server.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

% Recv logic WILL NOT re-attempt connection establishment on failure
-define(DefaultRecvTimeout, 100).
-define(DefaultMaxRerecvCount, 3).
-define(DefaultMaxReconnectCount, 10).
-define(DefaultServiceSessionId, 16#01).

% One server instance per hostname/port combination with synchronous behaviour

-record(state, {socket,
                % Not the overall recv timeout because of retrys
                recv_timeout,
                max_rerecv_count,
                service_pipe,
                service_session_id,
                header_size,
                header_handler,
                header_handler_context,
                server_ref = make_ref()}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions = 
        [fun (_NProps, _Context, State) ->
            gen_server:cast(self(), {cont_service, State#state.server_ref}),
            {true, State}
         end],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "socket",
                   index = #state.socket,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "service_pipe",
                   index = #state.service_pipe,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "service_session_id",
                   index = #state.service_session_id,
                   directive = default,
                   dirvalue = ?DefaultServiceSessionId},
         #propdesc{name = "header_size",
                   index = #state.header_size,
                   ret_type = integer,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "header_handler",
                   index = #state.header_handler,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "header_handler_context",
                   index = #state.header_handler_context,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "recv_timeout",
                   index = #state.recv_timeout,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultRecvTimeout},
         #propdesc{name = "max_rerecv_count",
                   index = #state.max_rerecv_count,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultMaxRerecvCount}],
        InitFunctions,
        ok,
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
%% cont_service
%%----------------------------------------------------------------------------

handle_cast({cont_service, _Ref}, State = #state{socket = undefined}) ->
    ?LogIt({handle_cast, cont_service}, "No socket. Exiting."),
    % Should not return. May have to use kill versus normal.
    NState = close(State),
    exit(normal),
    {noreply, NState};

handle_cast({cont_service, Ref}, State = #state{server_ref = Ref}) ->
    NState = cont_service(State),
    {noreply, NState};

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

handle_cast(close, State) ->
    NState = close(State),
    % Should not return. May have to use kill versus normal.
    exit(normal),
    {noreply, NState};

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
%% cont_service
%%----------------------------------------------------------------------------

cont_service(State) ->
    AState =
        case attempt_read(State) of
            {{error, _Reason}, NState} ->
                % Redundant
                close(NState);
            {{Header, Payload}, NState} ->
                forward_data(Header, Payload, NState)
        end,
    receive_next_request(AState).

%%----------------------------------------------------------------------------
%% receive_next_request
%%----------------------------------------------------------------------------

receive_next_request(State = #state{server_ref = Ref}) ->
    gen_server:cast(self(), {cont_service, Ref}),
    State.

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

close(State = #state{socket = undefined}) ->
    State;
close(State = #state{socket = Socket}) ->
    gen_tcp:shutdown(Socket, read),
    gen_tcp:close(Socket),
    State#state{socket = undefined}.

%%----------------------------------------------------------------------------
%% forward_data
%%----------------------------------------------------------------------------

forward_data(Header, 
             Payload, 
             State = #state{service_pipe = Pipe, 
                            service_session_id = SessionId}) ->
    pur_utls_pipes:send_to_next({Header, Payload}, SessionId, Pipe),
    State.

%%----------------------------------------------------------------------------
%% attempt_read
%%----------------------------------------------------------------------------

attempt_read(State = #state{max_rerecv_count = Count}) ->
    attempt_read(Count, State).

attempt_read(_NumTrys, State = #state{socket = undefined}) ->
    {{error, not_connected}, State};
attempt_read(NumTrys, State) ->
    pur_utls_misc:iterate(NumTrys, {ignore, State}, fun try_read/2).

%%----------------------------------------------------------------------------
%% try_read
%%----------------------------------------------------------------------------

% We loose the original error.
try_read(_Count, {_, State = #state{socket = undefined}}) ->
    {false, {{error, connection_failure}, State}};
try_read(_Count, {_, 
                  State = #state{socket = Socket, 
                                 header_size = Size}}) ->
    case gen_tcp:recv(Socket, Size) of
        {ok, Packet} ->
            retrieve_payload(Packet, State);
        {error, Reason} when Reason == ebadf;
                             Reason == econnreset;
                             Reason == epipe;
                             Reason == etimedout;
                             Reason == econnaborted;
                             Reason == enobufs  ->
            ?LogIt(try_read, 
                   "gen_tcp:recv(...) failed with: ~p, which is being "
                       "treated as a designated connection failure. "
                       "Will not retry recv.",
                   [Reason]),
            CState = close(State),
            {false, {{error, connection_failure}, CState}};
        {error, Reason} ->
            ?LogIt(try_read, 
                   "gen_tcp:recv(...) failed with: ~p, which is being "
                       "treated as a possible connection failure. "
                       "Will not retry recv.",
                   [Reason]),
            CState = close(State),
            {false, {{error, connection_failure}, CState}}
    end.

%%----------------------------------------------------------------------------
%% retrieve_payload
%%----------------------------------------------------------------------------

retrieve_payload(Header, State) ->
    retrieve_payload(first, Header, State).

retrieve_payload(Try,
                 Header,
                 State = #state{socket = Socket, 
                                header_handler = Handler,
                                header_handler_context = Context,
                                recv_timeout = Timeout}) ->
    Ret = 
        case Handler(Header, Context) of
            {ok, PayloadSize} ->
                case gen_tcp:recv(Socket, PayloadSize, Timeout) of
                    {ok, Payload} ->
                        {false, {{Header, Payload}, State}};
                    {error, timeout} ->
                        % Hack. Implies that this gen_server should be a
                        %     fsm, or the retrieve_pdu(...) behavior should be
                        %     at lease be driven from the try_read(...) 
                        %     iterate count behaviour above. REVISIT
                        retrieve_payload(second, Header, State);
                    {error, Reason} ->
                        ?LogIt(retrieve_payload, 
                               "gen_tcp:recv(...) failed for PDU "
                                   "retrieval with: ~p. This is being "
                                   "treated as a connection failure where "
                                   "this modbus read will fail, and result "
                                   "in a closed connection.",
                               [Reason]),
                        CState = close(State),
                        {false, {{error, Reason}, CState}}
                end;
            R = {error, _Status} ->
                % Ignoring bad requests for now.
                {false, {R, State}}
        end,
    if 
        Try == first ->
            Ret;
        true ->
            case Ret of
                {true, {Status = {error, _}, NState}} ->
                   ?LogIt(retrieve_payload, 
                           "gen_tcp:recv(...) failed for second PDU "
                               "retrieval. This is being treated as a "
                               "connection failure where this modbus read "
                               "will fail, and close the connection."),
                    CCState = close(NState),
                    {false, {Status, CCState}};
                _ ->
                    Ret
            end
    end.

