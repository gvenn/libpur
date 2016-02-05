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

-ifndef(PUR_UTLS_MISC_HRL).
-define(PUR_UTLS_MISC_HRL, true).

-define(LogItRaw(Message),
        error_logger:warning_report(Message)).

-define(LogItMessage(FunctionId, SuffixFormat),
        ?LogItMessage(FunctionId, SuffixFormat, [])).

%-define(LogItMessage(FunctionId, SuffixFormat, Args),
%        io_lib:format("~p:~p " ++ SuffixFormat, 
%                      [?MODULE, FunctionId|Args])).

-define(LogItMessage(FunctionId, SuffixFormat, Args),
    io_lib:format(
        "~s", 
        [lists:flatten(io_lib:format("~p:~p " ++ SuffixFormat,
                                     [?MODULE, FunctionId|Args]))])).

-define(LogItWithTraceMessage(FunctionId, SuffixFormat),
        ?LogItWithTraceMessage(FunctionId, SuffixFormat, [])).

-define(LogItWithTraceMessage(FunctionId, SuffixFormat, Args),
        ?LogItMessage(FunctionId, 
                      SuffixFormat ++ "~nWith stack trace:~n~p", 
                      Args ++ [erlang:get_stacktrace()])).

-define(LogIt(FunctionId, SuffixFormat),
        ?LogIt(FunctionId, SuffixFormat, [])).

-define(LogIt(FunctionId, SuffixFormat, Args),
        ?LogItRaw(?LogItMessage(FunctionId, SuffixFormat, Args))).

-define(LogItWithTrace(FunctionId, SuffixFormat),
        ?LogItWithTrace(FunctionId, SuffixFormat, [])).

-define(LogItWithTrace(FunctionId, SuffixFormat, Args),
        ?LogItRaw(?LogItWithTraceMessage(FunctionId, SuffixFormat, Args))).

-define(DebugItRaw(Message),
        io:format(Message)).

-define(DebugIt(FunctionId, SuffixFormat),
        ?DebugIt(FunctionId, SuffixFormat, [])).

-define(DebugIt(FunctionId, SuffixFormat, Args),
        ?DebugItRaw(?LogItMessage(FunctionId, SuffixFormat, Args))).

-define(DebugItWithTrace(FunctionId, SuffixFormat),
        ?DebugItWithTrace(FunctionId, SuffixFormat, [])).

-define(DebugItWithTrace(FunctionId, SuffixFormat, Args),
        ?DebugItRaw(?LogItWithTraceMessage(FunctionId, SuffixFormat, Args))).

-define(ThrowFlat(Message), throw(lists:flatten(Message))).

-endif.



