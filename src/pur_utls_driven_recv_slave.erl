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

-module(pur_utls_driven_recv_slave).

%%%%%%%%%%%%%%%%%%%
% Being a gen_server let alone a pipe server is overkill. However development
%     will proceed faster so going with it, until there is more time. REVISIT
%%%%%%%%%%%%%%%%%%%

-behavior(pur_utls_pipe_server).

% Synchronous implementation

-export([spawn/4, spawn/3,
         read_next_payload/2,
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
                next_payload_size = 0,
                server_ref = make_ref()}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions = [],
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

handle_call(create_direct_call_handle, 
            _From, 
            State = #state{socket = undefined}) ->
    {reply, {error, "non_functioning socket"}, State};
handle_call(create_direct_call_handle, 
            _From, 
            State = #state{socket = Socket, 
                           recv_timeout = Timeout, 
                           max_rerecv_count = Count}) ->
    Context = #state{socket = Socket,
                     recv_timeout = Timeout,
                     max_rerecv_count = Count},
    {reply, {fun direct_read_next_payload/2, Context}, State};

%%----------------------------------------------------------------------------
%% read_next_payload
%%----------------------------------------------------------------------------

handle_call({read_next_payload, _Size}, 
            _From,
            State = #state{socket = undefined}) ->
    ?LogIt({handle_call, read_next_payload}, "No socket. Exiting."),
    % Should not return. May have to use kill versus normal.
    NState = close(State),
    {stop, normal, NState};
handle_call({read_next_payload, Size}, _From, State) ->
    case read_next_payload(Size, State) of
        {R = {error, _Reason}, NState} ->
            {reply, R, NState};
        {Result, NState} ->
            {reply, Result, NState} 
    end;

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
%% read_next_payload
%%----------------------------------------------------------------------------

handle_cast({read_next_payload, _Size}, 
        State = #state{socket = undefined}) ->
    ?LogIt({handle_cast, read_next_payload}, "No socket. Exiting."),
    % Should not return. May have to use kill versus normal.
    NState = close(State),
    {stop, normal, NState};
handle_cast({read_next_payload, Size}, State) ->
    case read_next_payload(Size, State) of
        {R = {error, _Reason}, NState} ->
            FState = forward_data(R, NState),
            {noreply, FState};
        {Result, NState} ->
            FState = forward_data(Result, NState),
            {noreply, FState} 
    end;

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

handle_cast({exit_service, Ref}, State = #state{server_ref = Ref}) ->
    NState = close(State),
    % Should not return. May have to use kill versus normal.
    {stop, normal, NState};

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

handle_cast(close, State) ->
    NState = close(State),
    % Should not return. May have to use kill versus normal.
    {stop, normal, NState};

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
%% read_next_payload pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = _SessionId}, read_next_payload, _Size},
            State = #state{socket = undefined}) ->
    ?LogIt({handle_pipe, read_next_payload}, "No socket. Exiting."),
    % Should not return. May have to use kill versus normal.
    {stop, normal, State};
handle_pipe({#pipe_context{session_id = SessionId}, read_next_payload, Size},
            State) ->
    {Result, RState} = read_next_payload(Size, State),
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
%% direct_read_next_payload
%%----------------------------------------------------------------------------

direct_read_next_payload(Size, Context) ->
    case attempt_read(Size, Context) of
        {R = {error, Reason}, NContext} ->
            % Redundant
            ?LogIt(direct_read_next_payload, 
                   "attempt_read failed with: ~p.",
                   [Reason]),
            {R, close(NContext)};
        R = {{ok, _Payload}, _NContext} ->
            R
    end.

%%----------------------------------------------------------------------------
%% read_next_payload
%%----------------------------------------------------------------------------

read_next_payload(Size, State) ->
    case attempt_read(Size, State) of
        {R = {error, Reason}, NState} ->
            % Redundant
            ?LogIt(read_next_payload, 
                   "attempt_read failed with: ~p. Exiting.",
                   [Reason]),
            {R, exit_service(NState)};
        R = {{ok, _Payload}, _NState} ->
            R
    end.

%%----------------------------------------------------------------------------
%% receive_next_request
%%----------------------------------------------------------------------------

exit_service(State = #state{server_ref = Ref}) ->
    gen_server:cast(self(), {exit_service, Ref}),
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

forward_data(Payload, 
             State = #state{service_pipe = Pipe, 
                            service_session_id = SessionId}) ->
    pur_utls_pipes:send_to_next(Payload, SessionId, Pipe),
    State.

%%----------------------------------------------------------------------------
%% attempt_read
%%----------------------------------------------------------------------------

attempt_read(Size, State = #state{max_rerecv_count = Count}) ->
    attempt_read(Count, Size, State).

attempt_read(_NumTrys, _Size, State = #state{socket = undefined}) ->
    {{error, not_connected}, State};
attempt_read(NumTrys, Size, State) ->
    case pur_utls_misc:iterate(NumTrys, 
                               {ignore, Size, State}, 
                               fun try_read/2) of
        {Result, _, NState} -> {Result, NState};
        R -> R
    end.

%%----------------------------------------------------------------------------
%% try_read
%%----------------------------------------------------------------------------

% We loose the original error.
try_read(_Count, {_, _Size, State = #state{socket = undefined}}) ->
    {false, {{error, connection_failure}, State}};
try_read(_Count, {_, Size, State = #state{socket = Socket, 
                                          recv_timeout = Timeout}}) ->
    case gen_tcp:recv(Socket, Size, Timeout) of
        {ok, Packet} ->
            {false, {{ok, Packet}, State}};
        {error, timeout} ->
            % Note: We are NOT treating this as an immediate error!
            ?LogIt(try_read, 
                   "gen_tcp:recv(...) failed with timeout: ~p, for size: ~p. "
                       "May retry recv.",
                   [Timeout, Size]),
            {true, {{error, timeout}, Size, State}};
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
            {false, {{error, connection_failure}, State}};
        {error, Reason} ->
            ?LogIt(try_read, 
                   "gen_tcp:recv(...) failed with: ~p, which is being "
                       "treated as a possible connection failure. "
                       "Will not retry recv.",
                   [Reason]),
            {false, {{error, connection_failure}, State}}
    end.

