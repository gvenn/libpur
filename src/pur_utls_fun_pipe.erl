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

-module(pur_utls_fun_pipe).

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

-record(fun_capture, {module, function}).
-record(state, {call_fun, cast_fun, info_fun, pipe_fun, fun_state}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    SetFun =
        fun (NProps, Index, {NameModule, NameFunction, Arity}, State) ->
            case pur_utls_props:set_from_props(
                     NProps,
                     [#propdesc{name = NameModule,
                                index = #fun_capture.module,
                                ret_type = atom,
                                directive = required,
                                dirvalue = false},
                      #propdesc{name = NameFunction,
                                index = #fun_capture.function,
                                ret_type = atom,
                                directive = required,
                                dirvalue = false}],
                     #fun_capture{}) of
                {true, #fun_capture{module = undefined, 
                                    function = _}} ->
                    {true, setelement(Index, State, undefined)};
                {true, #fun_capture{module = _, 
                                    function = undefined}} ->
                    {true, setelement(Index, State, undefined)};
                {true, #fun_capture{module = Module, 
                                    function = Function}} ->
                    {true, 
                     setelement(Index, State, fun Module:Function/Arity)};
                {false, Reason, _} -> 
                    {false, Reason, State}
            end
        end,
    InitFunctions =
        [fun (NProps, _Context, State) ->
            SetFun(NProps, #state.call_fun, {call_module, call_fun, 4}, State)
         end,
         fun (NProps, _Context, State) ->
            SetFun(NProps, #state.cast_fun, {cast_module, cast_fun, 3}, State)
         end,
         fun (NProps, _Context, State) ->
            SetFun(NProps, #state.info_fun, {info_module, info_fun, 3}, State)
         end,
         fun (NProps, _Context, State) ->
            SetFun(NProps, #state.pipe_fun, {pipe_module, pipe_fun, 2}, State)
         end],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = fun_state,
                   index = #state.fun_state,
                   directive = required,
                   dirvalue = true}],
        InitFunctions,
        [],
        #state{}).

terminate(Reason, State) ->
    case Reason of
        normal -> ok;
        shutdown -> ok;
        {shutdown, _} -> ok;
        Reason -> ?LogIt(terminate,
                         "Terminated for reason: ~n~p, ~nwith state:~n~p.",
                         [Reason, State])
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
%% fun call expression
%%----------------------------------------------------------------------------

handle_call(_Expr, _From, State = #state{call_fun = undefined}) ->
    {reply, undefined, State};
handle_call(Expr, From, State = #state{call_fun = Fun, 
                                       fun_state = FunState}) ->
    case Fun(call, Expr, From, FunState) of
        {reply, Reply, FState} -> 
            {reply, Reply, State#state{fun_state = FState}};
        % Timeout includes hibernate
        {reply, Reply, FState, Timeout} -> 
            {reply, Reply, State#state{fun_state = FState}, Timeout};
        {noreply, FState} -> 
            {noreply, State#state{fun_state = FState}};
        % Timeout includes hibernate
        {noreply, FState, Timeout} -> 
            {noreply, State#state{fun_state = FState}, Timeout};
        {stop, Reason, FState} -> 
            {stop, Reason, State#state{fun_state = FState}};
        {stop, Reason, Reply, FState} -> 
            {stop, Reason, Reply, State#state{fun_state = FState}}
    end.

%%----------------------------------------------------------------------------
%% handle_cast
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% fun cast expression
%%----------------------------------------------------------------------------

handle_cast(_Expr, State = #state{cast_fun = undefined}) ->
    {noreply, State};
handle_cast(Expr, State = #state{cast_fun = Fun, fun_state = FunState}) ->
    case Fun(cast, Expr, FunState) of
        {noreply, FState} -> 
            {noreply, State#state{fun_state = FState}};
        % Timeout includes hibernate
        {noreply, FState, Timeout} -> 
            {noreply, State#state{fun_state = FState}, Timeout};
        {stop, Reason, FState} -> 
            {stop, Reason, State#state{fun_state = FState}}
    end.

%%----------------------------------------------------------------------------
%% handle_info
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% fun info expression
%%----------------------------------------------------------------------------

handle_info(_Expr, State = #state{info_fun = undefined}) ->
    {noreply, State};
handle_info(Expr, State = #state{info_fun = Fun, fun_state = FunState}) ->
    case Fun(info, Expr, FunState) of
        {noreply, FState} -> 
            {noreply, State#state{fun_state = FState}};
        % Timeout includes hibernate
        {noreply, FState, Timeout} -> 
            {noreply, State#state{fun_state = FState}, Timeout};
        {stop, Reason, FState} -> 
            {stop, Reason, State#state{fun_state = FState}}
    end.

%%----------------------------------------------------------------------------
%% handle_pipe
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% fun pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, _Term, Expr}, 
            State = #state{pipe_fun = undefined}) ->
    % Skips to next in pipe
    {reply, Expr, SessionId, State};
handle_pipe({PipeContext = #pipe_context{session_id = SessionId}, Term, Expr}, 
            State = #state{pipe_fun = Fun, fun_state = FunState}) ->
    case Fun({PipeContext, Term, Expr}, FunState) of
        {noreply, FState} ->
            {noreply, SessionId, State#state{fun_state = FState}};
        % Timeout includes hibernate
        {noreply, FState, Timeout} -> 
            {noreply, SessionId, State#state{fun_state = FState}, Timeout};
        {reply, Reply, FState} ->
            {reply, Reply, SessionId, State#state{fun_state = FState}};
        % Timeout includes hibernate
        {reply, Reply, FState, Timeout} -> 
            {reply, 
             Reply, SessionId, State#state{fun_state = FState}, Timeout};
        {stop, Reason, FState} -> 
            {stop, Reason, State#state{fun_state = FState}}
    end.

%%----------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% "Spawn" Behavior
%%----------------------------------------------------------------------------

spawn(nolink, Name = {global, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, pur_utls_fun_pipe}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, Name, NStartArgs, StartOptions);
spawn(nolink, Name = {local, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, pur_utls_fun_pipe}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, Name, NStartArgs, StartOptions);
spawn(link, Name = {global, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, pur_utls_fun_pipe}|StartArgs],
    pur_utls_pipe_server:spawn(link, Name, NStartArgs, StartOptions);
spawn(link, Name = {local, _RegName}, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, pur_utls_fun_pipe}|StartArgs],
    pur_utls_pipe_server:spawn(link, Name, NStartArgs, StartOptions).

spawn(nolink, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, pur_utls_fun_pipe}|StartArgs],
    pur_utls_pipe_server:spawn(nolink, NStartArgs, StartOptions);
spawn(link, StartArgs, StartOptions) ->
    NStartArgs = [{callback_module, pur_utls_fun_pipe}|StartArgs],
    pur_utls_pipe_server:spawn(link, NStartArgs, StartOptions).

%%----------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------


