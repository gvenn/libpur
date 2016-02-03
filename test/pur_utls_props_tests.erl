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

-module(pur_utls_props_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").

-record(record_test, {one, two, three, four, five}).

basic_tuple_test() ->
    Tuple = erlang:make_tuple(5, undefined),
    Keys = ["one", "two", "three", "four", "five"],
    Values = lists:seq(1,5),
    Props = lists:zip(Keys, lists:map(fun (X) -> integer_to_list(X) end, 
                                      Values)),
    {_, RDesc} = 
        lists:foldl(
            fun (Name, {Index, Acc}) ->
                {Index + 1, [#propdesc{name = Name, 
                                       index = Index,
                                       ret_type = integer}|Acc]}
            end,
            {1, []},
            Keys),
    Descriptors = lists:reverse(RDesc),
    TestTuple = {true, list_to_tuple(Values)},
    ResultTuple = pur_utls_props:set_from_props(Props, Descriptors, Tuple),
    %?LogIt(basic_tuple_test, 
    %       "~nTestTuple: ~p,~nResultTuple: ~p.", 
    %       [TestTuple, ResultTuple]),
    ?assert(TestTuple =:= ResultTuple).

basic_record_test() ->
    Record = #record_test{},
    Keys = ["one", "two", "three", "four", "five"],
    Values = lists:seq(1,5),
    Props = lists:zip(Keys, lists:map(fun (X) -> integer_to_list(X) end, 
                                      Values)),
    {_, RDesc} = 
        lists:foldl(
            fun (Name, {Index, Acc}) ->
                {Index + 1, [#propdesc{name = Name, 
                                       index = Index,
                                       ret_type = integer}|Acc]}
            end,
            {2, []},
            Keys),
    Descriptors = lists:reverse(RDesc),
    TestRecord = {true, 
                  #record_test{one = 1, 
                               two = 2, 
                               three = 3, 
                               four = 4, 
                               five = 5}},
    ResultRecord = pur_utls_props:set_from_props(Props, Descriptors, Record),
    %?LogIt(basic_record_test, 
    %       "~nTestRecord: ~p,~nResultRecord: ~p.", 
    %       [TestRecord, ResultRecord]),
    ?assert(TestRecord =:= ResultRecord).

transform_record_test() ->
    Record = #record_test{},
    Keys = ["one", "two", "three", "four", "five"],
    Values = lists:seq(1,5),
    Props = lists:zip(Keys, lists:map(fun (X) -> integer_to_list(X) end, 
                                      Values)),
    Transform =
        fun (Value, _, _, _, _) ->
            integer_to_list(pur_utls_props:convert(integer, Value) + 100)
        end,
    {_, RDesc} = 
        lists:foldl(
            fun (Name, {Index, Acc}) ->
                {Index + 1, [#propdesc{name = Name, 
                                       index = Index,
                                       % Not used when Transform is in effect
                                       ret_type = integer,
                                       transform = Transform}|Acc]}
            end,
            {2, []},
            Keys),
    Descriptors = lists:reverse(RDesc),
    TestRecord = {true, 
                  #record_test{one = "101", 
                               two = "102", 
                               three = "103", 
                               four = "104", 
                               five = "105"}},
    ResultRecord = pur_utls_props:set_from_props(Props, Descriptors, Record),
    %?LogIt(basic_record_test, 
    %       "~nTestRecord: ~p,~nResultRecord: ~p.", 
    %       [TestRecord, ResultRecord]),
    ?assert(TestRecord =:= ResultRecord).

usage_test_() ->
    M = pur_utls_props,
    % E = fun (Expr) -> element(1, Expr) end,
    Keys = ["one", "two", "three", "four", "five"],
    Values = lists:seq(1,5),
    Props = lists:zip(Keys, lists:map(fun (X) -> integer_to_list(X) end, 
                                      Values)),

    [?_assert(
        {true, #record_test{one = <<"1">>, four = 4, five = "5 + 1"}} =:=
            M:set_from_props(
                Props,
                [#propdesc{name = one, 
                           index = #record_test.one,
                           ret_type = binary,
                           directive = required,
                           dirvalue = true},
                 #propdesc{name = "four",
                           index = #record_test.four,
                           ret_type = integer,
                           directive = required,
                           dirvalue = true},
                 #propdesc{name = "six",
                           index = #record_test.five,
                           directive = default,
                           dirvalue = "5 + 1"}],
                 #record_test{})),
     begin
         {Status, _Reason, _PartialResult} =
             M:set_from_props(
                 Props,
                 [#propdesc{name = one, 
                            index = #record_test.one,
                            ret_type = binary,
                            directive = required,
                            dirvalue = true},
                  #propdesc{name = "four.5",
                            index = #record_test.four,
                            ret_type = integer,
                            directive = required,
                            dirvalue = true},
                  #propdesc{name = "six",
                            index = #record_test.five,
                            directive = default,
                            dirvalue = "5 + 1"}],
                  #record_test{}),
         ?_assert(false =:= Status)
     end].

-endif.

