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

-module(pur_utls_props).

-export([set_from_props/3, convert/2]).

-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").

%%----------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% set_from_props
%%----------------------------------------------------------------------------

set_from_props(Props, Descriptors, ToSet) when 
        is_tuple(ToSet),
        is_list(Props), 
        is_list(Descriptors) ->
    case lists:foldl(fun set_from_prop/2,
                     {Props, true, "", ToSet},
                     Descriptors) of
        {_, false, Reason, Result} -> {false, Reason, Result};
        {_, true, _, Result} -> {true, Result}
    end.

%%----------------------------------------------------------------------------
%% convert
%%----------------------------------------------------------------------------

convert(integer, Value) ->
    convert_to_integer(Value);
convert(float, Value) ->
    convert_to_float(Value);
convert(atom, Value) ->
    convert_to_atom(Value);
convert(list, Value) ->
    convert_to_list(Value);
convert(binary, Value) ->
    convert_to_binary(Value);
convert(map, Value) ->
    convert_to_map(Value).

%%----------------------------------------------------------------------------
%% Internal Functions
%%----------------------------------------------------------------------------

%%----------------------------------------------------------------------------
%% set_from_prop
%%----------------------------------------------------------------------------

set_from_prop(Descriptor = #propdesc{directive = undefined},
              ContextState = {_Props, true, _Reason, _TupleToSet}) ->
    set_from_prop(Descriptor#propdesc{directive = required, dirvalue = false}, 
                  ContextState);
set_from_prop(Desc = #propdesc{name = PropName, 
                               index = TupleIndex},
              {Props, true, _, TupleToSet}) when
        is_integer(TupleIndex) ->
    case find_prop(Desc, Props, TupleToSet) of
        ok -> 
            {Props, true, "", TupleToSet};
        {ok, Result} ->
            {Props, true, "", setelement(TupleIndex, TupleToSet, Result)};
        error ->
            Reason = ?LogItWithTraceMessage(
                         set_from_prop,
                         "PropName: ~p, not found.~n",
                         [PropName]),
            {Props, false, Reason, TupleToSet};
        {error, Reason} ->
            {Props, false, Reason, TupleToSet}
    end;
set_from_prop(Desc = #propdesc{index = [LastIndex]},
              SecondArg = {_Props, true, _, _TupleToSet}) ->
    set_from_prop(Desc#propdesc{index = LastIndex}, SecondArg);
% NOT Tail Recursive
set_from_prop(Desc = #propdesc{index = [NextIndex|RIndicies]},
              {Props, true, Reason, OuterTuple}) ->
    InnerTuple = element(NextIndex, OuterTuple),
    case set_from_prop(Desc#propdesc{index = RIndicies},
                       {Props, true, Reason, InnerTuple}) of
        {Props, true, Reason, NInnerTuple} ->
            NOuterTuple = setelement(NextIndex, OuterTuple, NInnerTuple),
            {Props, true, Reason, NOuterTuple};
        {Props, Flag, Reason, _} ->
            {Props, Flag, Reason, OuterTuple}
    end;
set_from_prop(_,
              ToRet = {_Props, false, _Reason, _TupleToSet}) ->
    ToRet.
           
%%----------------------------------------------------------------------------
%% find_prop
%%----------------------------------------------------------------------------

find_prop(Desc = #propdesc{name = PropName}, Props, TupleContext) when 
        is_list(PropName) ->
    find_prop(list, atom, Desc, Props, TupleContext);
find_prop(Desc = #propdesc{name = PropName}, Props, TupleContext) when 
        is_atom(PropName) ->
    find_prop(atom, list, Desc, Props, TupleContext).

find_prop(atom, 
          list, Desc = #propdesc{name = PropName}, Props, TupleContext) ->
    case proplists:get_value(PropName, Props) of
        undefined ->
            find_prop(list, 
                      list, 
                      Desc#propdesc{name = atom_to_list(PropName)}, 
                      Props, 
                      TupleContext);
        Value ->
            apply_transform(Value, Desc, Props, TupleContext)
    end;
find_prop(list, 
          atom, Desc = #propdesc{name = PropName}, Props, TupleContext) ->
    case proplists:get_value(PropName, Props) of
        undefined ->
            find_prop(list, 
                      list, 
                      Desc#propdesc{name = list_to_atom(PropName)}, 
                      Props,
                      TupleContext);
        Value ->
            apply_transform(Value, Desc, Props, TupleContext)
    end;
find_prop(_CurrentTry, 
          _CurrentTry,
          #propdesc{name = PropName, 
                    directive = default, 
                    dirvalue = DefValue},
          Props, 
          _TupleContext) ->
    % Will not apply transform or validation for default values
    {ok, proplists:get_value(PropName, Props, DefValue)};
find_prop(_CurrentTry,
          _CurrentTry,
          Desc = #propdesc{name = PropName, 
                           directive = required, 
                           dirvalue = false},
          Props, 
          TupleContext) ->
    case proplists:get_value(PropName, Props) of
        undefined -> ok;
        Value -> apply_transform(Value, Desc, Props, TupleContext)
    end;
find_prop(_CurrentTry,
          _CurrentTry,
          Desc = #propdesc{name = PropName, 
                           directive = required, 
                           dirvalue = true},
          Props, 
          TupleContext) ->
    case proplists:get_value(PropName, Props) of
        undefined -> error;
        Value -> apply_transform(Value, Desc, Props, TupleContext)
    end.

%%----------------------------------------------------------------------------
%% apply_transform
%%----------------------------------------------------------------------------

apply_transform(Value, 
                Desc = #propdesc{ret_type = undefined,
                                 transform = undefined}, 
                Props, 
                TupleContext) ->
    apply_validation(Value, Desc, Props, TupleContext);
apply_transform(Value, 
                Desc = #propdesc{transform = Transform, 
                                 transform_context = Context},
                Props,
                TupleContext) when
        is_function(Transform, 5) ->
    apply_validation(Transform(Value, Props, Desc, Context, TupleContext), 
                     Desc,
                     Props,
                     TupleContext);
apply_transform(Value, 
                Desc = #propdesc{ret_type = undefined,
                                 transform = Transform},
                Props,
                TupleContext) ->
    % Not to be suppressed
    ?LogIt(apply_transform, 
           "Transform: ~p, not understood. Ignoring.", 
           [Transform]),
    apply_validation(Value, Desc, Props, TupleContext);
apply_transform(Value, 
                Desc = #propdesc{ret_type = Type,
                                 transform = undefined}, 
                Props, 
                TupleContext) ->
    apply_validation(convert(Type, Value), Desc, Props, TupleContext).

    
%%----------------------------------------------------------------------------
%% apply_validation
%%----------------------------------------------------------------------------

apply_validation(Value, 
                #propdesc{validation = undefined}, 
                _Props, 
                _TupleContext) ->
    {ok, Value};
apply_validation(Value, 
                Desc = #propdesc{validation = Validate, 
                                 validation_context = Context},
                Props,
                TupleContext) when
        is_function(Validate, 5) ->
    case Validate(Value, Props, Desc, Context, TupleContext) of
        error -> {error, ?LogItMessage(apply_validation, 
                                       "Validation: ~p of ~p failed in "
                                           "context: ~p.", 
                                       [Validate, Value, Context])};
        R -> R
    end.

%%----------------------------------------------------------------------------
%% convert_to_integer
%%----------------------------------------------------------------------------

% Does not support maps

convert_to_integer(Value) when is_integer(Value) ->
    Value;
convert_to_integer(Value) when is_float(Value) ->
    round(Value);
convert_to_integer(Value) when is_atom(Value) ->
    list_to_integer(atom_to_list(Value));
convert_to_integer(Value) when is_list(Value) ->
    list_to_integer(Value);
convert_to_integer(Value) when is_binary(Value) ->
    binary_to_integer(Value).

%%----------------------------------------------------------------------------
%% convert_to_float
%%----------------------------------------------------------------------------

% Does not support maps

convert_to_float(Value) when is_integer(Value) ->
    float(Value);
convert_to_float(Value) when is_float(Value) ->
    Value;
convert_to_float(Value) when is_atom(Value) ->
    list_to_float(atom_to_list(Value));
convert_to_float(Value) when is_list(Value) ->
    list_to_float(Value);
convert_to_float(Value) when is_binary(Value) ->
    binary_to_float(Value).

%%----------------------------------------------------------------------------
%% convert_to_atom
%%----------------------------------------------------------------------------

% Does not support maps

convert_to_atom(Value) when is_integer(Value) ->
    checked_list_to_atom(integer_to_list(Value));
convert_to_atom(Value) when is_float(Value) ->
    checked_list_to_atom(float_to_list(Value));
convert_to_atom(Value) when is_atom(Value) ->
    Value;
convert_to_atom(Value) when is_list(Value) ->
    checked_list_to_atom(Value);
convert_to_atom(Value) when is_binary(Value) ->
    binary_to_atom(Value, utf8).

%%----------------------------------------------------------------------------
%% convert_to_list
%%----------------------------------------------------------------------------

convert_to_list(Value) when is_integer(Value) ->
    integer_to_list(Value);
convert_to_list(Value) when is_float(Value) ->
    float_to_list(Value);
convert_to_list(Value) when is_atom(Value) ->
    atom_to_list(Value);
convert_to_list(Value) when is_list(Value) ->
    Value;
convert_to_list(Value) when is_binary(Value) ->
    binary_to_list(Value);
convert_to_list(Value) when is_map(Value) ->
    maps:to_list(Value).

%%----------------------------------------------------------------------------
%% convert_to_binary
%%----------------------------------------------------------------------------

% Does not support maps

convert_to_binary(Value) when is_integer(Value) ->
    integer_to_binary(Value);
convert_to_binary(Value) when is_float(Value) ->
    float_to_binary(Value);
convert_to_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
convert_to_binary(Value) when is_list(Value) ->
    list_to_binary(Value);
convert_to_binary(Value) when is_binary(Value) ->
    Value.

%%----------------------------------------------------------------------------
%% convert_to_map
%%----------------------------------------------------------------------------

-ifdef(pur_supports_18).
convert_to_map(Value) when is_map(Value) ->
    Value;
convert_to_map(Value) when is_list(Value) ->
    maps:from_list(Value);
convert_to_map(Value) when is_integer(Value) ->
    #{Value => Value};
convert_to_map(Value) when is_float(Value) ->
    #{Value => Value};
convert_to_map(Value) when is_atom(Value) ->
    #{Value => Value};
convert_to_map(Value) when is_binary(Value) ->
    #{Value => Value}.
-else.
convert_to_map(Value) when is_map(Value) ->
    Value;
convert_to_map(Value) when is_list(Value) ->
    maps:from_list(Value);
convert_to_map(Value) when is_integer(Value) ->
    maps:put(Value, Value, #{});
convert_to_map(Value) when is_float(Value) ->
    maps:put(Value, Value, #{});
convert_to_map(Value) when is_atom(Value) ->
    maps:put(Value, Value, #{});
convert_to_map(Value) when is_binary(Value) ->
    maps:put(Value, Value, #{}).
-endif.

%%----------------------------------------------------------------------------
%% checked_list_to_atom
%%----------------------------------------------------------------------------

checked_list_to_atom(Value) ->
    try
        list_to_existing_atom(Value)
    catch _Class:_Error ->
        list_to_atom(Value)
    end.

