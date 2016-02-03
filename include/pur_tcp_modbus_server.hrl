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

-ifndef(PUR_TCP_MODBUS_SERVER).
-define(PUR_TCP_MODBUS_SERVER, true).

% Exceptions are one of:
-define(ModbusExceptions, [illegal_function, 
                           illegal_data_address,
                           illegal_data_value,
                           server_device_failure,
                           acknowledge,
                           server_device_busy,
                           memory_parity_error,
                           gateway_path_unavailable,
                           gateway_target_device_failed_to_respond]).

-record(response_id, {request_id, 
                      % The following are the modbus associated params
                      trans_id, 
                      unit_id, 
                      funct_code}).

-endif.



