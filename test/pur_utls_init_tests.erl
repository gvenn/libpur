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

-module(pur_utls_init_tests).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include_lib("pur_utls_misc.hrl").
-include_lib("pur_utls_props.hrl").

-record(record_test, {one, two, three, four, five}).

no_functions_test() ->
    M = pur_utls_init,
    % E = fun (Expr) -> element(1, Expr) end,
    Keys = ["one", "two", "three", "four", "five"],
    Values = lists:seq(1,5),
    Props = lists:zip(Keys, lists:map(fun (X) -> integer_to_list(X) end, 
                                      Values)),
    ?assert(
        {true, #record_test{one = <<"1">>, four = 4, five = "5 + 1"}} =:=
            M:auto_set(Props,
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
                        [],
                        #record_test{})).

functions_test() ->
    M = pur_utls_init,
    % E = fun (Expr) -> element(1, Expr) end,
    Keys = ["one", "two", "three", "four", "five"],
    Values = lists:seq(1,5),
    Props = lists:zip(Keys, lists:map(fun (X) -> integer_to_list(X) end, 
                                      Values)),
    FunContext = {},
    Functions = 
        [fun (_NProps, _NFunContext, R = #record_test{one = <<"1">>}) ->
            {true, R#record_test{one = <<"1 + mod">>}}
         end,
         fun (_NProps, _NFunContext, R = #record_test{four = ToInc}) ->
             {true, R#record_test{four = ToInc + 100}}
         end],
    ?assert(
        {true, #record_test{one = <<"1 + mod">>, 
                            four = 104, 
                            five = "5 + 1"}} =:=
            M:auto_set(Props,
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
                        Functions,
                        FunContext,
                        #record_test{})).

functions_fail_test() ->
    M = pur_utls_init,
    % E = fun (Expr) -> element(1, Expr) end,
    Keys = ["one", "two", "three", "four", "five"],
    Values = lists:seq(1,5),
    Props = lists:zip(Keys, lists:map(fun (X) -> integer_to_list(X) end, 
                                      Values)),
    FunContext = {},
    FunFailReason = "Second fun failed",
    Functions = 
        [fun (_NProps, _NFunContext, R = #record_test{one = <<"1">>}) ->
            {true, R#record_test{one = <<"1 + mod">>}}
         end,
         fun (_NProps, _NFunContext, R = #record_test{four = _ToInc}) ->
             {false, FunFailReason, R}
         end],
    {Status, Reason, #record_test{one = <<"1 + mod">>, 
                                  four = 4, 
                                  five = "5 + 1"}} =
        M:auto_set(Props,
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
                    Functions,
                    FunContext,
                    #record_test{}),
    ?assert({Status, Reason} =:= {false, FunFailReason}).

functions_nest_set_test() ->
    M = pur_utls_init,
    N = pur_utls_props,
    % E = fun (Expr) -> element(1, Expr) end,
    Keys = ["one", "two", "three", "four", "five", "other"],
    Values = lists:seq(1,6),
    Props = lists:zip(Keys, lists:map(fun (X) -> integer_to_list(X) end, 
                                      Values)),
    FunContext = other,
    Functions = 
        [fun (_NProps, _NFunContext, R = #record_test{one = <<"1">>}) ->
            {true, R#record_test{one = <<"1 + mod">>}}
         end,
         fun (_NProps, _NFunContext, R = #record_test{four = ToInc}) ->
             {true, R#record_test{four = ToInc + 100}}
         end,
         fun (NProps, NameContext, R = #record_test{}) ->
             N:set_from_props(NProps,
                              [#propdesc{name = NameContext,
                                         index = #record_test.five,
                                         ret_type = integer,
                                         directive = required,
                                         dirvalue = true}],
                              R)
         end],
    Result =
        M:auto_set(Props,
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
                    Functions,
                    FunContext,
                    #record_test{}),
    %?LogIt(functions_nest_set_test, 
    %       "Result: ~p.", 
    %       [Result]),
    ?assert(
        {true, #record_test{one = <<"1 + mod">>, 
                            four = 104, 
                            five = 6}} =:= Result).

-endif.

