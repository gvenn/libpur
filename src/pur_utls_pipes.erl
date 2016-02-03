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

-module(pur_utls_pipes).

-export([send_to_next/3, cast_to_pipe/2, reset_session/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").

%%----------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% send_to_next
%%----------------------------------------------------------------------------

send_to_next(Message, SessionId, [Next = #pipecomp{}|RPipeComps]) ->
    send_to(Message, SessionId, Next, RPipeComps);
send_to_next(_Message, _SessionId, []) ->
    ok;
send_to_next(Message, SessionId, [L|R]) when is_list(L) ->
    send_to_next(Message, SessionId, L),
    send_to_next(Message, SessionId, R).

%%----------------------------------------------------------------------------
%% cast_to_pipe
%%----------------------------------------------------------------------------

cast_to_pipe({Module, Term, State}, {Exec, Message, PipeContext}) ->
    NPipeContext = set_with_session(PipeContext),
    Module:Term({NPipeContext, Exec, Message}, State).

%%----------------------------------------------------------------------------
%% reset_session
%%----------------------------------------------------------------------------

reset_session(#pipe_context{name = CompName,
                            pipe_name = PipeName,
                            session_id = undefined}) ->
    clear_session([pipes, PipeName, CompName, session]);
reset_session(#pipe_context{name = CompName,
                            pipe_name = PipeName,
                            session_id = Id,
                            session_context = Session}) ->
    set_session([pipes, PipeName, CompName, session, Id], Session).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Have not yet designed for funs, fsms, or normal sends
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%----------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% send_to
%%----------------------------------------------------------------------------

send_to(Message, 
        SessionId, 
        #pipecomp{name = Name,
                  pipe_name = PipeName,
                  type = Type, 
                  pipe_context = Context,
                  exec = Exec, 
                  to = To},
        RestPipeComps) ->
    PipeContext = #pipe_context{name = Name,
                                pipe_name = PipeName,
                                context = Context,
                                session_id = SessionId,
                                pipe = RestPipeComps},
    case Type of
        function ->
            Exec(PipeContext, To, Message);
        cast ->
            gen_server:cast(To, {PipeContext, Exec, Message});
        event ->
            gen_fsm:send_event(To, {PipeContext, Exec, Message});
        all_events ->
            gen_fsm:send_all_state_event(To, {PipeContext, Exec, Message});
        send ->
            To ! {PipeContext, Exec, Message}
    end.

%%----------------------------------------------------------------------------
%% set_with_session
%%----------------------------------------------------------------------------

set_with_session(Context = #pipe_context{session_id = undefined}) ->
    Context;
set_with_session(Context = #pipe_context{pipe_name = PipeName,
                                         name = CompName,
                                         session_id = Id}) ->
    case get(?MODULE) of
        undefined ->
            Context;
        ProcessContext ->
            case nest_find([pipes, PipeName, CompName, session, Id], 
                           ProcessContext) of
                error -> 
                    clear_session([pipes, PipeName, CompName, session]); 
                Session -> 
                    Context#pipe_context{session_context = Session}
            end
    end.

%%----------------------------------------------------------------------------
%% nest_find
%%----------------------------------------------------------------------------

nest_find([], Context) ->
    Context;
nest_find([NextId|RIds], Context) ->
    case dict:find(NextId, Context) of
        error -> 
            error;
        {ok, NContext} -> 
            nest_find(RIds, NContext)
    end.

%%----------------------------------------------------------------------------
%% clear_session
%%----------------------------------------------------------------------------

clear_session(Keys) -> 
    NewContext =
        case get(?MODULE) of
            undefined -> clear_session(Keys, dict:new());
            Context -> clear_session(Keys, Context)
        end,
    put(?MODULE, NewContext),
    NewContext.
                

clear_session(Keys, Context) -> 
    {?MODULE, NContext} =  
        try_nest_set(force, Keys, dict:new(), [{?MODULE, Context}]),
    NContext.

%%----------------------------------------------------------------------------
%% set_session
%%----------------------------------------------------------------------------

set_session(Keys, Session) ->
    StartContext =
        case get(?MODULE) of
            undefined -> dict:new();
            Context -> Context
        end,
    NewContext = set_session(Keys, Session, StartContext),
    put(?MODULE, NewContext).

set_session(Keys, Session, StartContext) ->
    {?MODULE, NewContext} =
        try_nest_set(force, Keys, Session, [{?MODULE, StartContext}]),
    NewContext.

%%----------------------------------------------------------------------------
%% nest_set
%%----------------------------------------------------------------------------

-ifdef(Unused).
nest_set(Keys, Value, KeyContextPairs) ->
    try_nest_set(false, Keys, Value, KeyContextPairs).
-endif.

%%----------------------------------------------------------------------------
%% force_nest_set
%%----------------------------------------------------------------------------

try_nest_set(_, [], _, [R = {_LastContextKey, _LastContext}]) ->
    R;
try_nest_set(ForceOption, 
             [],
             Unused, 
             [{StoreKey, ToStore}, {NextKey, ToStoreIn}|RContexts]) ->
    try_nest_set(
        ForceOption,
        [], 
        Unused, 
        [{NextKey, dict:store(StoreKey, ToStore, ToStoreIn)}|RContexts]);
try_nest_set(ForceOption, [Key], Value, Contexts) ->
    % Could skip this step
    try_nest_set(ForceOption, [], undefined, [{Key, Value}|Contexts]);
try_nest_set(ForceOption, [Key|NKeys], Value, R = [{_, Context}|_]) ->
    case dict:find(Key, Context) of
        error -> 
            case ForceOption of
                force ->
                    try_nest_set(force, 
                                 NKeys, dict:new(), [{Key, dict:new()}|R]);
                _ ->
                    error
            end;
        {ok, NewContext} ->  
            try_nest_set(ForceOption, NKeys, Value, [{Key, NewContext}|R])
    end.

