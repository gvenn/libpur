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

-module(pur_tcp_modbus_test_server).

-behavior(pur_utls_pipe_server).

-export([spawn/4, spawn/3,
         handle_call/3, handle_cast/2, handle_info/2, handle_pipe/2,
         terminate/2, code_change/3,
         init/1]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").
-include_lib("pur_utls_pipes.hrl").
-include_lib("pur_tcp_modbus_server.hrl").

%%----------------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------------

-record(state, {service_name, registers}).

%%----------------------------------------------------------------------------
%% "Init" Behavior
%%----------------------------------------------------------------------------

init(Props) -> 
    InitFunctions = [fun init_registers/3],
    pur_utls_server:auto_init(
        Props,
        [#propdesc{name = "service_name",
                   index = #state.service_name,
                   directive = default,
                   dirvalue = atom_to_list(?MODULE)},
         #propdesc{name = "registers",
                   index = #state.registers,
                   directive = required,
                   dirvalue = true}],
        InitFunctions,
        ok,
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

% These calls do not generate errors, and can add to initial list of 
%    registers.

%%----------------------------------------------------------------------------
%% set_registers
%%----------------------------------------------------------------------------

handle_call({set_registers, Base, []}, _From, State) when is_integer(Base) ->
    {reply, ok, State};
handle_call({set_registers, Base, Values}, _From, State) when 
        is_integer(Base), is_list(Values) ->
    NState = set_registers(Base, Values, State),
    {reply, ok, NState};

%%----------------------------------------------------------------------------
%% get_registers
%%----------------------------------------------------------------------------

handle_call({get_registers, Base, Number}, _From, State) when 
        is_integer(Base), is_integer(Number) ->
    {Reply, NState} = get_registers(Base, Number, State),
    {reply, Reply, NState};

%%----------------------------------------------------------------------------
%% build_pipe_component
%%----------------------------------------------------------------------------

handle_call(build_pipe_handler, 
            _From, 
            State = #state{service_name = PName}) ->
    PipeComp = #pipecomp{name = ?MODULE,
                         type = cast,
                         exec = handle_request,
                         to = self(),
                         pipe_name = PName},
    {reply, [PipeComp], State};

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
%% handle_request pipe expression
%%----------------------------------------------------------------------------

handle_pipe({#pipe_context{session_id = SessionId}, 
             handle_request, 
             {RequestId, Request}}, 
            State) ->
    {Response, FState} =
        case handle_request(RequestId, Request, State) of
            {ok, IResponse, NState} ->
                {{RequestId, Request, IResponse}, NState};
            {Exception, NState} ->
                {{RequestId, Request, {exception, Exception}}, NState}
        end,
    {reply, Response, SessionId, FState};

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
%% init_registers
%%----------------------------------------------------------------------------

init_registers(_Props, _Context, State = #state{registers = RegProps}) ->
    Registers =
        lists:foldl(
            fun ({NextAddr, NextValue}, Acc) ->
                dict:store(NextAddr, NextValue, Acc)
            end,
            dict:new(),
            RegProps),
    {true, State#state{registers = Registers}}.

%%----------------------------------------------------------------------------
%% set_registers
%%----------------------------------------------------------------------------

set_registers(_Base, [], State) ->
    State;
set_registers(Base, Values, State = #state{registers = Regs}) ->
    {_, FRegs} =
        pur_utls_misc:iterate(
            length(Values), 
            {Values, Regs}, 
            fun (NCount, {[NextValue|RValues], NRegs}) ->
                {true, {RValues, dict:store(Base + NCount, NextValue, NRegs)}}
            end),
    State#state{registers = FRegs}.

%%----------------------------------------------------------------------------
%% get_registers
%%----------------------------------------------------------------------------

get_registers(Base, 
              Number, 
              State = #state{registers = Regs}) when Number > 0 ->
    FValues =
        pur_utls_misc:iterate(
            Number,
            [],
            fun (NCount, NValues) ->
                case dict:find(Base + NCount, Regs) of
                    {ok, NValue} -> 
                        {true, [NValue|NValues]};
                    error ->
                        {true, [undefined|NValues]}
                end
            end),
    {lists:reverse(FValues), State};
get_registers(_, _, State) ->
    {[], State}.

%%----------------------------------------------------------------------------
%% write_registers
%%----------------------------------------------------------------------------

write_registers(_Base, [], State) ->
    {ok, State};
write_registers(Base, Values, State = #state{registers = Regs}) ->
    {Status, _, FRegs} =
        pur_utls_misc:iterate(
            length(Values), 
            {ok, Values, Regs}, 
            fun (NCount, {_, [NextValue|RValues], NRegs}) ->
                Key = Base + NCount,
                case dict:find(Key, NRegs) of
                    {ok, _} ->
                        {true, {ok,
                                RValues, 
                                dict:store(Key, NextValue, NRegs)}};
                    error ->
                        {false, {illegal_data_address, [], Regs}}
                end
            end),
    {Status, State#state{registers = FRegs}}.

%%----------------------------------------------------------------------------
%% read_registers
%%----------------------------------------------------------------------------

read_registers(Base, 
               Number, 
               State = #state{registers = Regs}) when Number > 0 ->
    {Status, FValues} =
        pur_utls_misc:iterate(
            Number,
            {ok, []},
            fun (NCount, {_, NValues}) ->
                case dict:find(Base + NCount, Regs) of
                    {ok, NValue} -> 
                        {true, {ok, [NValue|NValues]}};
                    error ->
                        {false, {illegal_data_address, []}}
                end
            end),
    {Status, lists:reverse(FValues), State};
read_registers(_, _, State) ->
    {illegal_data_value, [], State}.

%%----------------------------------------------------------------------------
%% handle_request
%%----------------------------------------------------------------------------

% Test server does not currently distinguish between holding and input 
%    registers. So does not emulate modbus associated error conditions.
%    REVISIT

handle_request(Id = #response_id{}, 
               {read_holding_registers, Base, Number}, 
               State) ->
    handle_read_registers(Id, Base, Number, State);
handle_request(Id = #response_id{}, 
               {read_input_registers, Base, Number}, 
               State) ->
    handle_read_registers(Id, Base, Number, State);
handle_request(Id = #response_id{}, 
               {write_single_register, Base, Number, Values}, 
               State) ->
    handle_write_registers(Id, Base, Number, Values, State);
handle_request(Id = #response_id{}, 
               {write_multiple_registers, Base, Number, Values}, 
               State) ->
    handle_write_registers(Id, Base, Number, Values, State).

%%----------------------------------------------------------------------------
%% handle_read_registers
%%----------------------------------------------------------------------------

handle_read_registers(#response_id{}, Base, Number, State) when
        is_integer(Base), is_integer(Number) ->
    case read_registers(Base, Number, State) of
        R = {ok, _Values, _NState} ->
            R;
        {Exception, _, NState} ->
            {Exception, NState}
    end;
handle_read_registers(#response_id{}, _, _, State) ->
    {illegal_data_value, State}.

%%----------------------------------------------------------------------------
%% handle_write_registers
%%----------------------------------------------------------------------------

handle_write_registers(#response_id{}, Base, Number, Values, State) when
        is_integer(Base), 
        is_integer(Number), 
        is_list(Values), 
        length(Values) == Number ->
    case write_registers(Base, Values, State) of
        {ok, NState} ->
            {ok, Number, NState};
        R = {_Exception, _NState} ->
            R
    end;
handle_write_registers(#response_id{}, _, _, _, State) ->
    {illegal_data_value, State}.

            

