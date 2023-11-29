-- Copyright (c) 2023 James Cook
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--     http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
------------------------------------------------------------------------------
--
-- mysearch.e

global function replace(sequence target, object replacement, integer start, integer stop) -- stop=start)
	return target[1..start-1] & replacement & target[stop+1..$]
end function

global function match_replace(object needle, sequence haystack, object replacement, integer max) -- max=0)
	integer posn
	integer needle_len
	integer replacement_len
	integer scan_from
	integer cnt
	
	
	if max < 0 then
		return haystack
	end if
	
	cnt = length(haystack)
	if max != 0 then
		cnt = max
	end if
	
	if atom(needle) then
		needle = {needle}
	end if
	if atom(replacement) then
		replacement = {replacement}
	end if

	needle_len = length(needle) - 1
	replacement_len = length(replacement)

	scan_from = 1
	while 1 do
		posn = match_from(needle, haystack, scan_from)
		if not posn then
			exit
		end if
		haystack = replace(haystack, replacement, posn, posn + needle_len)

		cnt -= 1
		if cnt = 0 then
			exit
		end if
		scan_from = posn + replacement_len
	end while

	return haystack
end function
