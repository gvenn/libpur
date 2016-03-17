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

-module(pur_utls_pipe_server).
-behavior(gen_server).

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3,
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

-record(state, {callback_module, callback_state}).

%%----------------------------------------------------------------------------
%% Required Callback Behavior
%%----------------------------------------------------------------------------

-callback handle_pipe({#pipe_context{}, Term :: term(), Expr :: term()}, 
                      State :: term()) -> 
    {reply, Reply :: term(), SessionId :: term(), NCState :: term()} |
    {reply, Reply :: term(), SessionId :: term(), NCState :: term(), 
     Timeout :: hibernate | term()} |
    {noreply, SessionId :: term(), NCState :: term()} |
    {noreply, SessionId :: term(), NCState :: term(), 
     Timeout :: hibernate | term()} |
    {stop, Reason :: term(), NCState :: term()}.

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    CallbackInit = 
        fun (NProps, _Context, State = #state{callback_module = Module}) ->
            case Module:init(NProps) of
                {ok, CState} -> 
                    {true, State#state{callback_state = CState}};
                {ok, CState, _} -> 
                    {false, 
                     "timeouts unsupported", 
                     State#state{callback_state = CState}};
                {stop, Reason} ->
                    {false, Reason, State};
                ignore ->
                    {false, "received ignore", State}
            end
        end,
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "callback_module", 
                   index = #state.callback_module,
                   ret_type = atom,
                   directive = required,
                   dirvalue = true}],
        [CallbackInit],
        undefined,
        #state{}).

terminate(Reason, State = #state{callback_module = Module, 
                                 callback_state = CState}) ->
    Module:terminate(Reason, CState),
    case Reason of
        normal -> ok;
        shutdown -> ok;
        {shutdown, _} -> ok;
        Reason -> ?LogIt(terminate,
                         "Terminated for reason: ~n~p, ~nwith state:~n~p.",
                         [Reason, State])
    end.

code_change(OldVsn, 
            State = #state{callback_module = Module, 
                           callback_state = CState},
            Extra) ->
    case Module:code_change(OldVsn, CState, Extra) of
        {ok, NCState} -> {ok, State#state{callback_state = NCState}};
        R = {error, _Reason} -> R
    end.

%%----------------------------------------------------------------------------
%% Genserver Exported Behavior
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% handle_call
%%----------------------------------------------------------------------------

-ifdef(pur_supports_18).

%%----------------------------------------------------------------------------
%% Default call expression
%%----------------------------------------------------------------------------

handle_call(Expr, From, State = #state{callback_module = Module, 
                                       callback_state = CState}) ->
    case Module:handle_call(Expr, From, CState) of
        {reply, Reply, NCState} -> 
            {reply, Reply, State#state{callback_state = NCState}};
        % Timeout includes hibernate
        {reply, Reply, NCState, Timeout} -> 
            {reply, Reply, State#state{callback_state = NCState}, Timeout};
        {noreply, NCState} -> 
            {noreply, State#state{callback_state = NCState}};
        % Timeout includes hibernate
        {noreply, NCState, Timeout} -> 
            {noreply, State#state{callback_state = NCState}, Timeout};
        {stop, Reason, NCState} -> 
            {stop, Reason, State#state{callback_state = NCState}};
        {stop, Reason, Reply, NCState} -> 
            {stop, Reason, Reply, State#state{callback_state = NCState}}
    end.

-else. % pur_supports_18

%%----------------------------------------------------------------------------
%% kill
%%----------------------------------------------------------------------------

handle_call(kill, _From, State) ->
    {stop, normal, ok, State};

%%----------------------------------------------------------------------------
%% Default call expression
%%----------------------------------------------------------------------------

handle_call(Expr, From, State = #state{callback_module = Module, 
                                       callback_state = CState}) ->
    case Module:handle_call(Expr, From, CState) of
        {reply, Reply, NCState} -> 
            {reply, Reply, State#state{callback_state = NCState}};
        % Timeout includes hibernate
        {reply, Reply, NCState, Timeout} -> 
            {reply, Reply, State#state{callback_state = NCState}, Timeout};
        {noreply, NCState} -> 
            {noreply, State#state{callback_state = NCState}};
        % Timeout includes hibernate
        {noreply, NCState, Timeout} -> 
            {noreply, State#state{callback_state = NCState}, Timeout};
        {stop, Reason, NCState} -> 
            {stop, Reason, State#state{callback_state = NCState}};
        {stop, Reason, Reply, NCState} -> 
            {stop, Reason, Reply, State#state{callback_state = NCState}}
    end.

-endif. % pur_supports_18


%%----------------------------------------------------------------------------
%% handle_cast
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% #pipe_context{}
%%----------------------------------------------------------------------------

handle_cast({PipeContext = #pipe_context{pipe = Pipe}, Term, Expr}, 
            State = #state{callback_module = Module, 
                           callback_state = CState}) ->
    case pur_utls_pipes:cast_to_pipe({Module, handle_pipe, CState},
                                     {Term, Expr, PipeContext}) of
        {reply, Reply, SessionId, NCState} -> 
            pur_utls_pipes:send_to_next(Reply, SessionId, Pipe),
            {noreply, State#state{callback_state = NCState}};
        % Timeout includes hibernate
        {reply, Reply, SessionId, NCState, Timeout} -> 
            pur_utls_pipes:send_to_next(Reply, SessionId, Pipe),
            {noreply, State#state{callback_state = NCState}, Timeout};
        {noreply, SessionId, NCState} -> 
            pur_utls_pipes:send_to_next([], SessionId, Pipe),
            {noreply, State#state{callback_state = NCState}};
        % Timeout includes hibernate
        {noreply, SessionId, NCState, Timeout} -> 
            pur_utls_pipes:send_to_next([], SessionId, Pipe),
            {noreply, State#state{callback_state = NCState}, Timeout};
        {stop, Reason, NCState} -> 
            % NOT continuing with pipe
            {stop, Reason, State#state{callback_state = NCState}}
    end;

%%----------------------------------------------------------------------------
%% Default cast expression
%%----------------------------------------------------------------------------

handle_cast(Expr, State = #state{callback_module = Module, 
                                 callback_state = CState}) ->
    case Module:handle_cast(Expr, CState) of
        {noreply, NCState} -> 
            {noreply, State#state{callback_state = NCState}};
        % Timeout includes hibernate
        {noreply, NCState, Timeout} -> 
            {noreply, State#state{callback_state = NCState}, Timeout};
        {stop, Reason, NCState} -> 
            {stop, Reason, State#state{callback_state = NCState}}
    end.

%%----------------------------------------------------------------------------
%% handle_info
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% Default info expression
%%----------------------------------------------------------------------------

handle_info(Expr, State = #state{callback_module = Module, 
                                 callback_state = CState}) ->
    case Module:handle_info(Expr, CState) of
        {noreply, NCState} -> 
            {noreply, State#state{callback_state = NCState}};
        % Timeout includes hibernate
        {noreply, NCState, Timeout} -> 
            {noreply, State#state{callback_state = NCState}, Timeout};
        {stop, Reason, NCState} -> 
            {stop, Reason, State#state{callback_state = NCState}}
    end.

%%----------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% "Spawn" Behavior
%%----------------------------------------------------------------------------

spawn(nolink, Name = {global, _RegName}, StartArgs, StartOptions) ->
    gen_server:start(Name, ?MODULE, StartArgs, StartOptions);
spawn(nolink, Name = {local, _RegName}, StartArgs, StartOptions) ->
    gen_server:start(Name, ?MODULE, StartArgs, StartOptions);
spawn(link, Name = {global, _RegName}, StartArgs, StartOptions) ->
    gen_server:start_link(Name, ?MODULE, StartArgs, StartOptions);
spawn(link, Name = {local, _RegName}, StartArgs, StartOptions) ->
    gen_server:start_link(Name, ?MODULE, StartArgs, StartOptions).

spawn(nolink, StartArgs, StartOptions) ->
    gen_server:start(?MODULE, StartArgs, StartOptions);
spawn(link, StartArgs, StartOptions) ->
    gen_server:start_link(?MODULE, StartArgs, StartOptions).

%%----------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------


