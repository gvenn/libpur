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

-module(pur_utls_misc).

-export([iterate/2, iterate/3]).

-include_lib("pur_utls_misc.hrl").

iterate(Acc, Fun) ->
    iterate_int(inf, {true, Acc}, Fun).

iterate(Count, Acc, Fun) ->
    iterate_int(0, Count, {true, Acc}, Fun).

iterate_int(inf, {false, Acc}, _Fun) ->
    Acc;
iterate_int(inf, {true, Acc}, Fun) ->
    iterate_int(inf, Fun(Acc), Fun).

iterate_int(Count, Count, {_, Acc}, _) ->
    Acc;
iterate_int(_, _, {false, Acc}, _) ->
    Acc;
iterate_int(Count, Final, {true, Acc}, Fun) ->
    iterate_int(Count + 1, Final, Fun(Count, Acc), Fun).
