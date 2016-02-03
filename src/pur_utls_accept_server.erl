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

-module(pur_utls_accept_server).

-behavior(pur_utls_pipe_server).

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2, handle_pipe/2,
         terminate/2, code_change/3,
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

-define(DefaultMaxListenAttempts, 5).
-define(DefaultSendTimeout, 100).
-define(DefaultAcceptTimeout, 100).
-define(DefaultListenOptions, 
        [binary, {packet, raw}, {active, false}, {nodelay, true}]).

-record(state, {backlog, 
                accept_timeout, 
                port, 
                comm_module, 
                comm_props,
                socket,
                listen_ref = make_ref(),
                send_timeout,
                max_listen_attempts}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions =
        [],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "backlog", 
                   index = #state.backlog,
                   ret_type = integer,
                   directive = default,
                   dirvalue = 5},
         #propdesc{name = "accept_timeout",
                   index = #state.accept_timeout,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultAcceptTimeout},
         #propdesc{name = "port",
                   index = #state.port,
                   ret_type = integer,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "comm_module",
                   index = #state.comm_module,
                   ret_type = atom,
                   directive = required,
                   dirvalue = true},
         #propdesc{name = "comm_props",
                   index = #state.comm_props,
                   directive = default,
                   dirvalue = Props},
         #propdesc{name = "max_listen_attempts",
                   index = #state.max_listen_attempts,
                   directive = default,
                   dirvalue = ?DefaultMaxListenAttempts},
         #propdesc{name = "send_timeout",
                   index = #state.send_timeout,
                   ret_type = integer,
                   directive = default,
                   dirvalue = ?DefaultSendTimeout}],
        InitFunctions,
        ok,
        #state{}).

terminate(Reason, State) ->
    LState = stop_listen(State),
    case Reason of
        normal -> ok;
        shutdown -> ok;
        {shutdown, _} -> ok;
        Reason -> ?LogIt(terminate,
                         "Terminated for reason: ~n~p, ~nwith state:~n~p.",
                         [Reason, LState])
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
%% start
%%----------------------------------------------------------------------------

handle_call(start, _From, State) ->
    {Reply, NState} = start_listen(State),
    {reply, Reply, NState};

%%----------------------------------------------------------------------------
%% stop
%%----------------------------------------------------------------------------

handle_call(stop, _From, State) ->
    NState = stop_listen(State),
    {reply, ok, NState};

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
%% start
%%----------------------------------------------------------------------------

handle_cast(start, State) ->
    {_Reply, NState} = start_listen(State),
    {noreply, NState};

%%----------------------------------------------------------------------------
%% stop
%%----------------------------------------------------------------------------

handle_cast(stop, State) ->
    NState = stop_listen(State),
    {noreply, NState};

%%----------------------------------------------------------------------------
%% listen_cont
%%----------------------------------------------------------------------------

% Will generate a unknown listen_cont log when ref is not recognized, unless
%    not listening

handle_cast({listen_cont, _}, State = #state{socket = undefined}) ->
    {noreply, State};

handle_cast({listen_cont, Ref}, State = #state{listen_ref = Ref}) ->
    % This will hang until timeout
    NState = listen_cont(State),
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
%% start
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, start, _}, State) ->
    {Reply, NState} = start_listen(State),
    {reply, Reply, SessionId, NState};

%%----------------------------------------------------------------------------
%% stop
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, stop, _}, State) ->
    NState = stop_listen(State),
    {reply, ok, SessionId, NState};

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
%% start_listen
%%----------------------------------------------------------------------------

start_listen(State = #state{backlog = BackLog, 
                            port = Port,
                            socket = undefined,
                            send_timeout = SendTimeout,
                            max_listen_attempts = NumTrys}) ->
    Options =
        lists:filter(
            fun 
                ({send_timeout_close, _}) -> false;
                ({send_timeout, _}) -> false;
                (_EProp) -> true
            end,
            ?DefaultListenOptions),
    NOptions =
        [{backlog, BackLog}, {send_timeout, SendTimeout}|Options],
    case pur_utls_misc:iterate(NumTrys, 
                               {ignore, NOptions, State}, 
                               fun attempt_listen/2) of
        {ok, NState} ->
            {ok, listen(NState)};
        {R = {error, Reason}, _, NState} ->
            ?LogIt(
                start_listen,
                "Listen on port: ~p, generated an error: ~p. "
                    "Stopping attempts.",
                [Port, Reason]), 
            {R, NState}
    end;
start_listen(State) ->
    State.

%%----------------------------------------------------------------------------
%% stop_listen
%%----------------------------------------------------------------------------

stop_listen(State = #state{socket = undefined}) ->
    State;
stop_listen(State) ->
    close(State).

%%----------------------------------------------------------------------------
%% attempt_listen
%%----------------------------------------------------------------------------

attempt_listen(_, {_, Options, State = #state{socket = undefined,
                                              port = Port}}) ->
    case gen_tcp:listen(Port, Options) of
        {ok, Socket} ->
            LState = State#state{socket = Socket},
            {false, {ok, LState}};
        R = {error, Reason} ->
            ?LogIt(
                attempt_listen,
                "Listen on port: ~p, generated an error: ~p. May retry",
                [Port, Reason]), 
            {true, {R, Options, State}}
    end;
attempt_listen(_, {_, State}) ->
    {false, {ok, State}}.

%%----------------------------------------------------------------------------
%% listen_cont
%%----------------------------------------------------------------------------

listen_cont(State = #state{socket = undefined}) ->
    State;
listen_cont(State = #state{socket = Socket,
                           accept_timeout = Timeout}) ->
    case gen_tcp:accept(Socket, Timeout) of
        {ok, CommSocket} ->
            SState = spawn_comm_server(CommSocket, State),
            listen(SState);
        {error, timeout} ->
            listen(State);
        {error, system_limit} ->
            ?LogIt(
                listen_cont,
                "accept received a system_limit. Ignoring, though accepts "
                    "will continue to fail until condition is cleared."),
            listen(State);
        {error, Reason} ->
            ?LogIt(
                listen_cont,
                "accept received: ~p. Will force close socket. Will attempt "
                    "automatic listen socket re-creation. If this fails, "
                    "another start message must be received for this "
                    "service to be re-run. Not exiting.",
                [Reason]),
            gen_server:cast(self(), start),
            State
    end.

%%----------------------------------------------------------------------------
%% listen
%%----------------------------------------------------------------------------

listen(State = #state{socket = undefined}) ->
    State;
listen(State = #state{listen_ref = Ref}) ->
    gen_server:cast(self(), {listen_cont, Ref}),
    State.

%%----------------------------------------------------------------------------
%% close
%%----------------------------------------------------------------------------

close(State = #state{socket = undefined}) ->
    State;
close(State = #state{socket = Socket}) ->
    % GDEBUG
    ?LogIt(close, "closing socket: ~p.", [Socket]), 
    gen_tcp:shutdown(Socket, read),
    gen_tcp:close(Socket),
    State#state{socket = undefined}.

%%----------------------------------------------------------------------------
%% spawn_comm_server
%%----------------------------------------------------------------------------

spawn_comm_server(CommSocket,
                  State = #state{comm_module = CommModule,
                                 comm_props = CommProps}) ->
    case CommModule:spawn(nolink, [{socket, CommSocket}|CommProps], []) of
        {ok, _} -> 
            State;
        ignore ->
            ?LogIt(
                spawn_comm_server,
                "Received an ignore when starting comm server of "
                    "module: ~p. Ignoring this result.",
                [CommModule]), 
            State;
        {error, {already_started, _}} ->
            ?LogIt(
                spawn_comm_server,
                "Received an already_started when starting comm server of "
                    "module: ~p. Should not happen but ignoring result "
                    "regardless.",
                [CommModule]), 
            State;
        {error, Reason} ->
            ?LogIt(
                spawn_comm_server,
                "Received: ~p, when starting comm server of "
                    "module: ~p. Not sure what to do with this since "
                        "nothing at this time will receive this error. "
                        "Ignoring error.",
                [Reason, CommModule]), 
            State
    end.
    
