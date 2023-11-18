
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
