-- Copyright 2023 James Cook
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
-- ed_macro_mod, a recordable macro version of ed.ex
-- This is the original ed_macro_named.ex
------------------------------------------------------------------------------
		----------------------------------------------------------
		--       This Euphoria Editor was developed by          --
		--            Rapid Deployment Software.                --
		--                                                      --
		-- Permission is freely granted to anyone to modify     --
		-- and/or redistribute this editor (ed.ex, syncolor.e). --
		----------------------------------------------------------

-- This program can be run with:
--     eui  ed.ex (Windows or UNIX to use the current console Window)
-- or
--     euiw ed.ex (Windows will create a new Window you'll have to maximize)
--  
-- On XP some control-key combinations aren't recognized)
--
-- How it Works:
-- * Using gets(), ed reads and appends each line of text into a 2-d "buffer",
--   i.e. a sequence of sequences where each (sub)sequence contains one line.
-- * ed waits for you to press a key, and then fans out to one of many small
--   routines that each perform one editing operation.
-- * Each editing operation is responsible for updating the 2-d buffer variable
--   containing the lines of text, and for updating the screen to reflect any
--   changes. This code is typically fairly simple, but there can be a lot
--   of special cases to worry about.
-- * Finally, ed writes back each line, using puts()
-- * How multiple-windows works: When you switch to a new window, all the 
--   variables associated with the current window are bundled together and 
--   saved in a sequence, along with the 2-d text buffer for that window.
--   When you switch back, all of these state variables, plus the 2-d text
--   buffer variable for that window are restored. Most of the code in ed is 
--   not even "aware" that there can be multiple-windows.
----
--
-- On Non-Windows systems, I recommend using CrossOver (https://www.codeweavers.com/crossover).
-- Then, use eui.exe (Euphoria installation) for Windows (https://openeuphoria.org/).

-- (Possibly make a Webpage version of this program.)

-- \?hex\?
-- On Apple macOS: {194, 182} == ¶
-- Unicode symbols: (https://symbl.cc/en/)

-- No control keys, for international keyboards.

-- Comment out this line for international keyboards:
--with define USE_CONTROL_KEYS

-- NOTE: To use all features, in Windows,
-- Disable "Console shortcut Properties option": [x] "Enable Ctrl key shortcuts"

-- "Named" macros for business purposes. (reset to default keys)

-- New feature: save and load macros (to be completed)
-- New feature: 'b' menu item that allows you to insert HEX characters
-- Uses CONTROL_CHAR before and after a sequence representing special characters,
--  or a string of HEX characters, like the 'b' menu option
-- It primarily edits text files, but if a file doesn't have a line ending ('\n')
--  as the last character, it allows you to remove it on save (or write).

-- New feature: Large file support, using memory functions.
--  The program should take up less memory when opening files.

-- ED.EX from Euphoria v4.0.5 modified for recordable macros.
--  Current features are: 10 programmable macros -- ESC, j -- accesses the macro menu,
--  view/record/stop-record/select-current-macro from the macro menu,
--  F12 plays the current macro.

without type_check -- makes it a bit faster
without warning

include std/graphics.e
include std/graphcst.e
-- include std/get.e
include std/wildcard.e
include std/dll.e
include std/sequence.e
include std/os.e
include std/console.e
include std/filesys.e
include std/text.e

include myget.e as myget -- jjc
include std/eds.e -- jjc
include std/io.e -- jjc
include std/machine.e -- jjc
include std/math.e -- jjc
include std/pretty.e -- jjc
include std/types.e -- jjc
include std/search.e -- jjc
include euphoria/info.e -- jjc

--with trace

constant TRUE = 1, FALSE = 0

-- begin jjc, thanks K_D_R
-- patch to fix Linux screen positioning
-- I think this is J Brown's code:
procedure get_real_text_starting_position()
		sequence sss = ""
		integer ccc
		puts(1, 27&"[6n")
		while 1 do
			ccc = get_key()
			if ccc = 'R' then
				exit
			end if
			if ccc != -1 then
				sss &= ccc
			end if
		end while
		sss = sss[3..$]
		sequence aa, bb
		aa = value(sss[1..find(';', sss)-1])
		bb = value(sss[find(';', sss)+1..$])
		position(aa[2], bb[2])
end procedure
ifdef LINUX then
	get_real_text_starting_position()
end ifdef
-- end jjc

-- special input characters
ifdef USE_CONTROL_KEYS then
constant 
		 CONTROL_B = 2,
		 CONTROL_C = 3,
		 CONTROL_D = 4,   -- alternate key for line-delete  
		 CONTROL_L = 12,
		 CONTROL_N = 14,
		 CONTROL_P = 16,  -- alternate key for PAGE-DOWN in Linux.
						  -- DOS uses this key for printing or something.
		 CONTROL_R = 18,
		 CONTROL_T = 20,
		 CONTROL_U = 21,   -- alternate key for PAGE-UP in Linux
		 CONTROL_Y = 25 -- 25 and 26 suspended on OSX
elsedef
constant 
		 CONTROL_B = -999,
		 CONTROL_C = 1020096, -- Control+Break
		 CONTROL_D = -999,   -- alternate key for line-delete  
		 CONTROL_L = -999,
		 CONTROL_N = -999,
		 CONTROL_P = -999,  -- alternate key for PAGE-DOWN in Linux.
						  -- DOS uses this key for printing or something.
		 CONTROL_R = -999,
		 CONTROL_T = -999,
		 CONTROL_U = -999,   -- alternate key for PAGE-UP in Linux
		 CONTROL_Y = -999
end ifdef

integer ESCAPE, CR, NUM_PAD_ENTER, BS, HOME, END, CONTROL_HOME, CONTROL_END,
	PAGE_UP, PAGE_DOWN, INSERT, NUM_PAD_SLASH,
	DELETE, XDELETE, ARROW_LEFT, ARROW_RIGHT,
	CONTROL_ARROW_LEFT, CONTROL_ARROW_RIGHT, ARROW_UP, ARROW_DOWN,
	CONTROL_ARROW_UP, CONTROL_ARROW_DOWN, -- jjc
	F1, F10, F11, F12, TAB_KEY, -- jjc
	NUM_PAD_ASTRISK, NUM_PAD_PLUS, NUM_PAD_MINUS, NUM_PAD_LOCK, -- jjc
	CONTROL_DELETE  -- key for line-delete 
			-- (not available on some systems)
sequence delete_cmd, compare_cmd
integer SAFE_CHAR -- minimum ASCII char that's safe to display
integer MAX_SAFE_CHAR -- maximum ASCII char that's safe to display
sequence UNSAFE_CHARS -- jjc
sequence ignore_keys
sequence window_swap_keys
sequence window_name
		 
ifdef UNIX then
	TAB_KEY = '\t' -- jjc
	SAFE_CHAR = 32
	MAX_SAFE_CHAR = 255 -- jjc
	delete_cmd = "rm "
	compare_cmd = "diff "
	ESCAPE = 27
	CR = 10
	NUM_PAD_ENTER = 10
	BS = 127 -- 263
	HOME = 262 
	END = 360 
	CONTROL_HOME = CONTROL_T -- (top)
	CONTROL_END = CONTROL_B  -- (bottom)
	PAGE_UP = 339 
	PAGE_DOWN = 338 
	INSERT = 331
	DELETE = 330
	XDELETE = -999 -- 127 -- in xterm
	ARROW_LEFT = 260
	ARROW_RIGHT = 261
	CONTROL_ARROW_LEFT = CONTROL_L  -- (left)
	CONTROL_ARROW_RIGHT = CONTROL_R -- (right)
	ARROW_UP = 259
	ARROW_DOWN = 258
	CONTROL_ARROW_UP = CONTROL_Y
	CONTROL_ARROW_DOWN = CONTROL_N
	window_swap_keys = {265,266,267,268,269,270,271,272,273,274} -- F1 - F10
	F1 = 265
	F10 = 274
	F11 = 275
	F12 = 276
	CONTROL_DELETE = DELETE -- key for line-delete 
							-- (not available on some systems)
	NUM_PAD_SLASH = -999  -- Please check on console and Xterm
	NUM_PAD_ASTRISK = -999
	NUM_PAD_PLUS = -999
	NUM_PAD_MINUS = -999
	NUM_PAD_LOCK = -999 -- jjc
	ignore_keys = {}
elsifdef WINDOWS then
	object kc

	kc = key_codes()
	
	TAB_KEY = kc[KC_TAB] -- jjc
	--UNSAFE_CHARS = {0,13,179,219,220,221,222,223,244,245,249,250,254,255} -- jjc, 26 is interpreted as EOF (end of file)
	--SAFE_CHAR = 14
	SAFE_CHAR = 32 -- jjc
	MAX_SAFE_CHAR = 126 -- jjc
	delete_cmd = "del "
	compare_cmd = "fc /T " -- jjc, lookat, binary mode may need /B
	ESCAPE = 27
	CR = 13
	BS = 8
	HOME = kc[KC_HOME] --327
	END = kc[KC_END] --335
ifdef USE_CONTROL_KEYS then
	CONTROL_HOME = 1020416 -- HOME + KM_CONTROL -- 583
	CONTROL_END = 1020432 -- END + KM_CONTROL --591
elsedef
	CONTROL_HOME = -999
	CONTROL_END = -999
end ifdef
	PAGE_UP = kc[KC_PRIOR] --329
	PAGE_DOWN = kc[KC_NEXT] --337
	INSERT = kc[KC_INSERT] -- 338
	DELETE = kc[KC_DELETE] --339
	XDELETE = -999 -- never
	ARROW_LEFT = kc[KC_LEFT] -- 331
	ARROW_RIGHT = kc[KC_RIGHT] --333
ifdef USE_CONTROL_KEYS then
	CONTROL_ARROW_LEFT = ARROW_LEFT + KM_CONTROL --587
	CONTROL_ARROW_RIGHT = ARROW_RIGHT + KM_CONTROL --589
elsedef
	CONTROL_ARROW_LEFT = -999
	CONTROL_ARROW_RIGHT = -999
end ifdef
	ARROW_UP = kc[KC_UP] --328
	ARROW_DOWN = kc[KC_DOWN] -- 336
	-- begin jjc:
ifdef USE_CONTROL_KEYS then
	CONTROL_ARROW_UP = ARROW_UP + KM_ALT
	CONTROL_ARROW_DOWN = ARROW_DOWN + KM_ALT
elsedef
	CONTROL_ARROW_UP = -999
	CONTROL_ARROW_DOWN = -999
end ifdef
	-- end jjc
	window_swap_keys = {kc[KC_F1],
				kc[KC_F2],
				kc[KC_F3],
				kc[KC_F4],
				kc[KC_F5],
				kc[KC_F6],
				kc[KC_F7],
				kc[KC_F8],
				kc[KC_F9],
				kc[KC_F10]} -- F1 - F10
	F1 = kc[KC_F1] --315
	F10 = kc[KC_F10] --324  
	F11 = kc[KC_F11] --343
	F12 = kc[KC_F12] --344
	NUM_PAD_ENTER = kc[KC_RETURN] --284
	NUM_PAD_SLASH = kc[KC_DIVIDE] --309     
	NUM_PAD_ASTRISK = kc[KC_MULTIPLY]
	NUM_PAD_PLUS = kc[KC_ADD]
	NUM_PAD_MINUS = kc[KC_SUBTRACT]
	NUM_PAD_LOCK = kc[KC_NUMLOCK] -- jjc
ifdef USE_CONTROL_KEYS then
	CONTROL_DELETE = DELETE + KM_CONTROL --595 -- key for line-delete 
elsedef
	CONTROL_DELETE = -999
end ifdef
	ignore_keys = {kc[KC_CAPITAL], kc[KC_CONTROL]+KM_CONTROL, kc[KC_SHIFT]+KM_SHIFT, kc[KC_MENU]+KM_ALT}
	kc = 0
end ifdef

	window_name        = {"F01:","F02:","F03:","F04:","F05:","F06:","F07:","F08:","F09:","F10:"}

-------- START OF USER-MODIFIABLE PARAMETERS ---------------------------------- 

-- make your own specialized macro command(s):
constant macro_database_filename = "edm.edb" -- short for "ed_macro_named"

-- Change this when macro behavior changes:
-- uses myget.e, which allows C-style hexadecimals.
constant table_name = "jmsck56, ed_macro_named.ex, v0.0.7, " & platform_name() & ", " & version_string_short()

constant CUSTOM_KEY = F12
sequence CUSTOM_KEYSTROKES = HOME & "-- " & ARROW_DOWN -- jjc

object recording_macro = 0 -- jjc
sequence current_macro = "default"

-- Wrap to screen:
integer wrap_to_screen = 0 -- Boolean, 0 is, don't wrap to screen by default.

-- Starting CR line ending:
constant CONTROL_CHAR = 254  -- change funny control chars to this -- jjc
constant WINDOWS_CR = {"\r\n", "\\r\\n"}
constant LINUX_CR = {"\n", "\\n"}
constant APPLE_CR = {"\r", "\\r"}
constant BINARY_CR = {"",""}
ifdef WINDOWS then
	sequence line_ending = WINDOWS_CR -- or {"",""} for none
elsedef
	sequence line_ending = LINUX_CR
end ifdef

constant PROG_INDENT = 8  -- tab width for editing program source files -- jjc
			  -- (tab width is 8 for other files)
-- Euphoria files:
constant E_FILES = {".e", ".ex", ".exd", ".exw", ".pro", ".cgi", ".esp"}
-- program indent files:
constant PROG_FILES = E_FILES & {".c", ".h", ".bas"} 

constant WANT_COLOR_SYNTAX  = TRUE -- FALSE if you don't want
								   -- color syntax highlighting

constant WANT_AUTO_COMPLETE = TRUE -- FALSE if you don't want 
								   -- auto-completion of Euphoria statements

constant HOT_KEYS = TRUE  -- FALSE if you want to hit Enter after each command

-- cursor style: 
constant ED_CURSOR = THICK_UNDERLINE_CURSOR
			-- UNDERLINE_CURSOR
			-- HALF_BLOCK_CURSOR
			-- BLOCK_CURSOR
				   
-- number of lines on screen: (25,28,43 or 50)
constant INITIAL_LINES = 43,  -- when editor starts up
	 FINAL_LINES = 43     -- when editor is finished

-- colors
constant TOP_LINE_TEXT_COLOR = BLACK,
	 TOP_LINE_BACK_COLOR = BROWN, 
	 TOP_LINE_DIM_COLOR = BLUE,
	 BACKGROUND_COLOR = WHITE

-- colors needed by syncolor.e:
-- Adjust to suit your monitor and your taste.
global constant NORMAL_COLOR = BLACK,   -- GRAY might look better
		COMMENT_COLOR = RED,
		KEYWORD_COLOR = BLUE,
		BUILTIN_COLOR = MAGENTA,
		STRING_COLOR = GREEN,   -- BROWN might look better
		BRACKET_COLOR = {NORMAL_COLOR}--, YELLOW, BRIGHT_WHITE, -- jjc
				--BRIGHT_BLUE, BRIGHT_RED, BRIGHT_CYAN, -- jjc
				--BRIGHT_GREEN} -- jjc

-- number of characters to shift left<->right when you move beyond column 80
constant SHIFT = 4   -- 1..78 should be ok

-- name of edit buffer temp file for Esc m command
constant TEMPFILE = "editbuff.tmp"
constant MACRO_FILE = "macrobuf.tmp"

constant ACCENT = 0  -- Set to 1 enables read accented characters from
					 -- keyboard. Useful to write on spanish keyboard, 
					 -- may cause problems on Windows using us-international 
					 -- keyboard layout

-------- END OF USER-MODIFIABLE PARAMETERS ------------------------------------

-- begin jjc:
constant APPEND_MIN_SIZE = 30

integer first_time = TRUE
object last_key = 0
sequence macro_buffer = {}
integer macro_repeat = 1

function get_CUSTOM_KEYSTROKES(sequence key)
	integer rec_num
	if first_time != TRUE then
		if not equal(key, last_key) then
			rec_num = db_find_key(key)
			if rec_num > 0 then
				last_key = key
				CUSTOM_KEYSTROKES = db_record_data(rec_num)
			else
				CUSTOM_KEYSTROKES = {}
			end if
		end if
	end if
	return CUSTOM_KEYSTROKES
end function

procedure store_CUSTOM_KEYSTROKES(sequence key, sequence buf)
	integer rec_num
	if equal(key, last_key) then
		CUSTOM_KEYSTROKES = buf
	end if
	rec_num = db_find_key(key)
	if rec_num < 0 then
		if db_insert(key, buf) != DB_OK then
			set_top_line("Error: Unable to insert macro into database.")
			getc(0)
		end if
	elsif rec_num > 0 then
		db_replace_data(rec_num, buf)
	else
		set_top_line("Error: Current table is not set in database.") -- current table not set
		getc(0)
	end if
end procedure



-- Special keys that we can handle. Some are duplicates.
-- If you add more, you should list them here:
constant SPECIAL_KEYS = {ESCAPE, BS, DELETE, XDELETE, PAGE_UP, PAGE_DOWN,
			INSERT, HOME, END, 
			ARROW_LEFT, ARROW_RIGHT, ARROW_UP, ARROW_DOWN, 
			CONTROL_P, CONTROL_U, CONTROL_T, CONTROL_B,
			CONTROL_R, CONTROL_L, CONTROL_Y, CONTROL_N,
			CONTROL_DELETE, CONTROL_D,
			CONTROL_ARROW_LEFT, CONTROL_ARROW_RIGHT,
			CONTROL_ARROW_UP, CONTROL_ARROW_DOWN, -- jjc
			CONTROL_HOME, CONTROL_END,
			CUSTOM_KEY} & window_swap_keys & ignore_keys

-- output device:
constant SCREEN = 1

constant STANDARD_TAB_WIDTH = 8

constant MAX_WINDOWS = 10 -- F1..F10

type boolean(integer x)
	return x = TRUE or x = FALSE
end type

type natural(integer x)
	return x >= 0
end type

type positive_int(integer x)
	return x >= 1
end type

--begin jjc:
procedure cannot_allocate_msg() -- jjc
	set_top_line("The program has run out of memory. Try restarting your computer.")
	getc(0)
end procedure

-- Memory Mangagement, store lines as "C" strings with length.
-- Store "buffer" as a linked list, so large files can load faster.
-- struct node1 {
--      unsigned char * binary_ptr; // offset: 0
--      size_t len; // offset: pointer_size
--      struct node1 * prev; // offset: pointer_size * 2
--      struct node1 * next; // offset: pointer_size * 3
-- };
constant B_BEGIN = 1, B_END = 2
sequence buffer = {0,0} -- In-memory buffer where the file is manipulated.
-- This is a sequence where each element is a sequence
-- containing one line of text. Each line of text ends with '\n'
integer length_buffer = 0
integer buffer_pos = 0
atom buffer_ma = 0 -- the memory address of "buffer_pos" position in "buffer"

-- Variables that must be kept "up to date":

-- return buffer & {length_buffer, buffer_pos, buffer_ma}

ifdef BITS64 then
	constant pointer_size = 8
elsedef
	constant pointer_size = 4
end ifdef

function peek_address(object ma_n_length)
ifdef BITS64 then
	return peek8u(ma_n_length)
elsedef
	return peek4u(ma_n_length)
end ifdef
end function

procedure poke_address(atom ma, object x)
ifdef BITS64 then
	poke8(ma, x)
elsedef
	poke4(ma, x)
end ifdef
end procedure

-- buffer_free()
procedure buffer_free(sequence x)
	sequence tmp
	atom ma
-- trace(1)
	ma = x[B_BEGIN]
	for i = 1 to x[3] do
		tmp = peek_address({ma, 4})
		free(tmp[1]) -- free binary string: "(unsigned char *) binary_ptr"
		free(ma)
		-- set next
		ma = tmp[4]
	end for
end procedure
procedure buffer_make_empty()
-- trace(1)
	buffer_free(buffer & length_buffer)
	buffer = {0,0}
	length_buffer = 0
	buffer_pos = 0
	buffer_ma = 0
end procedure
procedure buffer_seek(integer i)
--seek lines
	-- is it closer to beginning, ending, or buffer_pos
	sequence tmp
	integer f, offset
-- trace(1)
	if i = buffer_pos then
		return
	end if
	if i < 1 or i > length_buffer then
		-- something went wrong.
		abort(1/0)
	end if
	tmp = math:abs({1,length_buffer,buffer_pos} - i) --here-- lookat buffer_pos and length_buffer
	f = find(math:min(tmp), tmp)
	switch f do -- without fallthru
	case 1 then
		if buffer[B_BEGIN] = 0 then
			buffer[B_BEGIN] = buffer[B_END]
		end if
		buffer_ma = buffer[B_BEGIN]
		buffer_pos = 1
	case 2 then
		if buffer[B_END] = 0 then
			buffer[B_END] = buffer[B_BEGIN]
		end if
		buffer_ma = buffer[B_END]
		buffer_pos = length_buffer
	case 3 then
		-- do nothing
	case else
		-- this code line should never be reached:
		abort(1/0)
	end switch
	
	-- iterate closer to i
	f = buffer_pos - i
	if f = 0 then
		return
	elsif f > 0 then
		-- cursor is going up
		offset = pointer_size * 2 -- prev
		--for j = f to 1 by -1 do
		while f != 0 do
			buffer_ma = peek_address(buffer_ma + offset)
			f -= 1
		end while
		--end for
	elsif f < 0 then
		-- cursor is going down
		offset = pointer_size * 3 -- next
		--for j = f to 1 do
		while f != 0 do
			buffer_ma = peek_address(buffer_ma + offset)
			f += 1
		end while
		--end for
	else
		-- this code line should never be reached:
		abort(1/0)
	end if
	buffer_pos = i
	-- should be done.
end procedure
procedure buffer_delete_node_at(integer i)
	sequence tmp
	atom prev, next
-- trace(1)
	buffer_seek(i)
	-- free memory first
	tmp = peek_address({buffer_ma, 4})
	free(tmp[1]) -- free binary string: "(unsigned char *) binary_ptr"
	free(buffer_ma)
	-- set prev, next
	prev = tmp[3]
	next = tmp[4]
	length_buffer -= 1
	if prev != 0 then
		poke_address(prev + (pointer_size * 3), next)
	else
		-- it is at the beginning of the memory buffer
		buffer[B_BEGIN] = next
	end if
	if next != 0 then
		poke_address(next + (pointer_size * 2), prev)
		buffer_ma = next
	else
		-- it is at the ending of the memory buffer
		buffer[B_END] = prev
		buffer_ma = prev
		buffer_pos = length_buffer
	end if
	-- make sure you update variables.
end procedure
function buffer_at_length(integer line_n)
-- get length(buffer[bline])
	atom len
-- trace(1)
	buffer_seek(line_n)
	len = peek_address(buffer_ma + pointer_size)
	return len
end function
function buffer_at(integer line_n)
-- get buffer[bline]
	sequence st, tmp
-- trace(1)
	buffer_seek(line_n)
	tmp = peek_address({buffer_ma, 2})
	st = peek(tmp)
	return st
end function
procedure set_buffer_at(integer line_n, sequence st)
-- set_buffer_at(b_line, line) -- jjc
	sequence tmp
	atom ma
-- trace(1)
	buffer_seek(line_n)
	tmp = peek_address({buffer_ma, 2}) -- only need the first two (2) addresses
	free(tmp[1]) -- free binary string: "(unsigned char *) binary_ptr"
	ma = allocate_string(st) -- note: it may have zeros (0) in it, so never use peek_string() on it, OK.
	if ma = 0 then
		cannot_allocate_msg()
		return
	end if
	poke_address(buffer_ma, {ma, length(st)})
end procedure

procedure buffer_append(sequence line)
	atom prev, str
-- trace(1)
	-- make sure both buffer[B_BEGIN] and buffer[B_END] are set
	buffer_ma = allocate(pointer_size * 4)
	if buffer_ma = 0 then
		cannot_allocate_msg()
		return
	end if
	prev = buffer[B_END]
	if prev != 0 then
		poke_address(prev + (pointer_size * 3), buffer_ma) -- in "prev", store pointer to "next"
	end if
	-- populate "buffer_ma"
	str = allocate_string(line)
	if str = 0 then
		cannot_allocate_msg()
		return
	end if
	poke_address(buffer_ma, {str,length(line),prev,0})
	length_buffer += 1
	buffer_pos = length_buffer
	buffer[B_END] = buffer_ma
	if buffer[B_BEGIN] = 0 then
		buffer[B_BEGIN] = buffer_ma
	end if
	-- should be done.
end procedure
procedure buffer_insert_nodes_at(integer line_n, sequence lines)
--buffer_insert_nodes_at(b_line+1, {xtail}) -- jjc
--buffer_insert_nodes_at(b_line, kill_buffer) -- jjc

-- Note: there is always at least one line stored in the memory for each "buffer"
-- If there is not, call "buffer_append()"
	atom prev, last, ma, str
-- trace(1)
	if length(lines) = 0 then
		return
	end if
	if line_n - 1 = length_buffer then
		-- append lines at end of buffer
		--for i = 1 to length(lines) do
		-- In Euphoria, length(lines) is set once, at the beginning of the "for loop"
		while length(lines) do
			buffer_append(lines[1]) -- subscript is the number one (1)
			lines = lines[2..$] -- faster to truncate large sequences
		end while
		--end for
		return
	end if
	buffer_seek(line_n)
	-- insert lines at current position
	-- create nodes, one at a time.
	prev = peek_address(buffer_ma + (pointer_size * 2))
	last = buffer_ma -- old buffer_ma, data is inserted before it, so it is "last"
	buffer_ma = allocate(pointer_size * 4) -- new buffer_ma, becomes first data item
	if buffer_ma = 0 then
		cannot_allocate_msg()
		return
	end if
	if prev != 0 then
		poke_address(prev + (pointer_size * 3), buffer_ma) -- in "prev", store pointer to "next"
	else
		buffer[B_BEGIN] = buffer_ma
	end if
	-- populate "buffer_ma"
	str = allocate_string(lines[1]) -- note: this subscript is one (1)
	if str = 0 then
		cannot_allocate_msg()
		return
	end if
	poke_address(buffer_ma, {str,length(lines[1]),prev}) -- note: this subscript is one (1)
	prev = buffer_ma -- new buffer_ma, becomes first data item, so it is "previous"
	for i = 2 to length(lines) do
		ma = allocate(pointer_size * 4)
		if ma = 0 then
			cannot_allocate_msg()
			return
		end if
		poke_address(prev + (pointer_size * 3), ma) -- in "prev", store pointer to "next"
		-- populate "ma"
		str = allocate_string(lines[i])
		if str = 0 then
			cannot_allocate_msg()
			return
		end if
		poke_address(ma, {str,length(lines[i]),prev})
		prev = ma
	end for
	poke_address(prev + (pointer_size * 3), last) -- in "prev", store pointer to "next"
	poke_address(last + (pointer_size * 2), prev) -- in "next", store pointer to "prev"
	length_buffer += length(lines)
	-- should be done.
end procedure

-- function buffer_self()
--      return buffer & {length_buffer, buffer_pos, buffer_ma}
-- end function
procedure set_buffer(sequence b)
-- trace(1)
	-- free old buffer, use "b" buffer as current buffer
	buffer_make_empty()
	buffer = b[1..2]
	length_buffer = b[3]
end procedure

-- buffer_copy()
function buffer_copy()
-- trace(1)
	sequence ret, tmp
	atom ma, ma_from, str, prev
	ret = repeat(0,2)
	if length_buffer = 0 then
		return ret & {length_buffer}
	end if
	ma = allocate(pointer_size * 4)
	if ma = 0 then
		cannot_allocate_msg()
		return ret & {length_buffer}
	end if
	ma_from = buffer[B_BEGIN]
	-- populate "ma"
	tmp = peek_address({ma_from,4})
	str = allocate(tmp[2] + 1)
	if str = 0 then
		cannot_allocate_msg()
		return ret & {length_buffer}
	end if
	mem_copy(str, tmp[1], tmp[2] + 1)
	poke_address(ma, {str,tmp[2], 0, 0}) -- sets "prev" to zero (0)
	ret[B_BEGIN] = ma
	for i = 2 to length_buffer do
		prev = ma
		ma = allocate(pointer_size * 4)
		if ma = 0 then
			cannot_allocate_msg()
			return ret & {length_buffer}
		end if
		poke_address(prev + (pointer_size * 3), ma) -- in "prev", store pointer to "next"
		ma_from = tmp[4]
		-- populate "ma"
		tmp = peek_address({ma_from,4})
		str = allocate(tmp[2] + 1)
		if str = 0 then
			cannot_allocate_msg()
			return ret & {length_buffer}
		end if
		mem_copy(str, tmp[1], tmp[2] + 1)
		poke_address(ma, {str,tmp[2], prev, 0}) -- sets "prev"
	end for
	poke_address(ma + (pointer_size * 3), 0) -- sets "next" to zero (0)
	ret[B_END] = ma
	return ret & {length_buffer}
end function

--end jjc.

positive_int screen_length  -- number of lines on physical screen
positive_int screen_width
integer wrap_length -- jjc

global sequence BLANK_LINE

positive_int window_base    -- location of first line of current window 
							-- (status line)
window_base = 1
positive_int window_length  -- number of lines of text in current window

sequence window_list -- state info for all windows
window_list = {0}

sequence buffer_list -- all buffers
buffer_list = {}

type window_id(integer x)
	return x >= 1 and x <= length(window_list)
end type

type buffer_id(integer x)
	return x >= 0 and x <= length(buffer_list)
end type

type window_line(integer x)
-- a valid line in the current window
	return x >= 1 and x <= window_length
end type

type screen_col(integer x)
-- a valid column on the screen
	return x >= 1 
end type

type buffer_line(integer x)
-- a valid buffer line
	return (x >= 1 and x <= length_buffer) or x = 1
end type

type char(integer x)
-- a character (including special key codes)
	return x >= 0 and x <= 511
end type

type extended_char(integer x)
	return char(x) or x = -1
end type

type file_number(integer x)
	return x >= -1
end type

-- jjc:
type is_bytes(sequence b)
	for i = 1 to length(b) do
		if not integer(b[i]) then
			return 0
		end if
		if b[i] > 255 then
			return 0
		end if
		if b[i] < 0 then
			return 0
		end if
	end for
	return 1
end type


sequence file_name   -- name of the file that we are editing

-- These are the critical state variables that all editing operations
-- must update:
buffer_line  b_line  -- current line in buffer
positive_int b_col   -- current character within line in buffer
window_line  s_line  -- line on screen corresponding to b_line
screen_col   s_col   -- column on screen corresponding to b_col
natural s_shift      -- how much the screen has been shifted (for >80)
s_shift = 0

boolean stop         -- indicates when to stop processing current buffer

sequence kill_buffer -- kill buffer of deleted lines or characters
kill_buffer = {}

boolean adding_to_kill  -- TRUE if still accumulating deleted lines/chars

boolean multi_color     -- use colors for keywords etc.
boolean auto_complete   -- perform auto completion of statements
boolean dot_e           -- TRUE if this is a .e/.ex file
boolean modified        -- TRUE if the file has been modified compared to  
						-- what's on disk
boolean editbuff        -- TRUE if temp file exists (Esc m)
editbuff = FALSE

atom buffer_version,    -- version of buffer contents
	my_buffer_version  -- last version used by current window
buffer_version = 0
my_buffer_version = 0

boolean control_chars,  -- binary file - view but don't save
	cr_removed      -- Linux: CR's were removed from DOS file (CR-LF)

natural start_line, start_col

sequence error_message

sequence file_history, command_history, search_history, replace_history, macro_file_history, macro_name_history -- jjc
file_history = {}
command_history = {}
search_history = {}
replace_history = {}
macro_file_history = {} -- jjc
macro_name_history = {} -- jjc

sequence config -- video configuration

window_id window_number -- current active window
window_number = 1

buffer_id buffer_number -- current active buffer
buffer_number = 0

sequence key_queue -- queue of input characters forced by ed
key_queue = {}

-- procedure delay(atom n)
-- -- an n second pause while a message is on the screen
--      atom t
-- 
--      t = time()
--      while time() < t + n do
--      end while
-- end procedure

procedure set_modified()
-- buffer differs from file
	modified = TRUE
	cursor(NO_CURSOR) -- hide cursor while we update the screen
	if not integer(buffer_version) then
		buffer_version = 0
	end if
	buffer_version += 1
end procedure

procedure clear_modified()
-- buffer is now same as file
	modified = FALSE
end procedure


natural edit_tab_width 

function tab(natural tab_width, positive_int pos)
-- compute new column position after a tab
	return (floor((pos - 1) / tab_width) + 1) * tab_width + 1
end function

function expand_tabs(natural tab_width, sequence line)
-- replace tabs by blanks in a line of text
	natural tab_pos, column, ntabs

	column = 1
	while TRUE do
		tab_pos = find('\t', line[column..$])
		if tab_pos = 0 then
			-- no more tabs
			return line
		else
			tab_pos += column - 1
		end if
		column = tab(tab_width, tab_pos)
		ntabs = 1
		while line[tab_pos+ntabs] = '\t' do
			ntabs += 1
			column += tab_width
		end while
		-- replace consecutive tabs by blanks
		line = line[1..tab_pos-1] & 
			   repeat(' ', column - tab_pos) &
			   line[tab_pos+ntabs..$]
	end while
end function

function indent_tabs(natural tab_width, sequence line)
-- replace leading blanks of a line with tabs
	natural i, blanks

	if length(line) < tab_width then
		return line
	end if
	i = 1
	while line[i] = ' ' do
		i += 1
	end while    
	blanks = i - 1    
	return repeat('\t', floor(blanks / tab_width)) & 
		   BLANK_LINE[1..remainder(blanks, tab_width)] &
		   line[i..$]
end function

function convert_tabs(natural old_width, natural new_width, sequence line)
-- retabulate a line for a new tab size
	if old_width = new_width then
		return line
	end if
	return indent_tabs(new_width, expand_tabs(old_width, line))
end function

-- color display of lines
include euphoria/syncolor.e

procedure reverse_video()
-- start inverse video
	text_color(TOP_LINE_TEXT_COLOR)
	bk_color(TOP_LINE_BACK_COLOR)
end procedure

procedure normal_video()
-- end inverse video
	text_color(NORMAL_COLOR)
	bk_color(BACKGROUND_COLOR)
end procedure

procedure ClearLine(window_line sline)
-- clear the current line on screen
	scroll(1, window_base + sline, window_base + sline)
end procedure

procedure ClearWindow()
-- clear the current window
	scroll(window_length, window_base+1, window_base+window_length)
end procedure

procedure ScrollUp(positive_int top, positive_int bottom)
-- move text up one line on screen
	scroll(+1, window_base + top, window_base + bottom)
end procedure

procedure ScrollDown(positive_int top, positive_int bottom)
-- move text down one line on screen
	scroll(-1, window_base + top, window_base + bottom)
end procedure

procedure set_absolute_position(natural window_line, positive_int column)
-- move cursor to a line and an absolute (non-shifted) column within
-- the current window
	position(window_base + window_line, column)
end procedure

procedure DisplayLine(buffer_line bline, window_line sline, boolean all_clear)
-- display a buffer line on a given line on the screen
-- if all_clear is TRUE then the screen area has already been cleared before getting here.
	sequence this_line, color_line, text
	natural last, last_pos, color, len
	
	this_line = expand_tabs(edit_tab_width, buffer_at(bline))
	last = length(this_line) - 1
	set_absolute_position(sline, 1)
	if multi_color then
		-- color display
		color_line = SyntaxColor(this_line)
		last_pos = 0
		
		for i = 1 to length(color_line) do
			-- display the next colored text segment
			color = color_line[i][1]
			text = color_line[i][2]
			len = length(text)
			if last_pos >= s_shift then
				text_color(color)
				puts(SCREEN, text)
			elsif last_pos+len > s_shift then
				-- partly left-of-screen
				text_color(color)
				puts(SCREEN, text[1+(s_shift-last_pos)..len])
				last_pos += len
			else
				-- left-of-screen
				last_pos += len
			end if
		end for
	else
		-- monochrome display
		if last > s_shift then
			puts(SCREEN, this_line[1+s_shift..last])
		end if
	end if
	if last-s_shift > screen_width then
		-- line extends beyond right margin 
		set_absolute_position(sline, screen_width)
		text_color(BACKGROUND_COLOR)
		bk_color(NORMAL_COLOR)
		puts(SCREEN, this_line[screen_width+s_shift])
		normal_video()
	elsif not all_clear then
		-- clear rest of screen line.
		puts(SCREEN, BLANK_LINE)
	end if
end procedure

procedure DisplayWindow(positive_int bline, window_line sline)
-- print a series of buffer lines, starting at sline on screen
-- and continue until the end of screen, or end of buffer
	boolean all_clear

	if sline = 1 then 
		ClearWindow()
		all_clear = TRUE
	else
		all_clear = FALSE
	end if

	for b = bline to length_buffer do
		DisplayLine(b, sline, all_clear)
		if sline = window_length then
			return
		else
			sline += 1
		end if
	end for
	-- blank any remaining screen lines after end of file
	for s = sline to window_length do
		ClearLine(s)
	end for
end procedure

procedure set_position(natural window_line, positive_int column)
-- Move cursor to a logical screen position within the window.
-- The window will be shifted left<->right if necessary.
-- window_line 0 is status line, window_line 1 is first line of text
	natural s
	
	if window_line = 0 then
		-- status line
		position(window_base + window_line, column)
	else
		s = s_shift
		while column-s_shift > screen_width do
			s_shift += SHIFT
		end while
		while column-s_shift < 1 do
			s_shift -= SHIFT
		end while
		if s_shift != s then
			-- display shifted window
			DisplayWindow(b_line - s_line + 1, 1)
		end if
		position(window_base + window_line, column-s_shift)
	end if
end procedure

constant ESCAPE_CHARS = "\\nr",
		 ESCAPED_CHARS = "\\\n\r"

function clean(sequence line)
-- replace control characters with a graphics character
-- Linux: replace CR-LF with LF (for now)
	integer c, i, len, f
	
	-- trace(1)
	if length(line) = 0 or line[$] != '\n' then
		line &= '\n'
	end if
	i = 1
	while i < length(line) do
	--for i = 1 to length(line)-1 do
		c = line[i]
-- 		if c < SAFE_CHAR and c != '\t' then
-- 			line[i] = CONTROL_CHAR  -- replace with displayable character
-- 			control_chars = TRUE
-- 		end if
		f = find(c, ESCAPED_CHARS)
		if f then -- jjc
			line = line[1..i-1] & "\\" & ESCAPE_CHARS[f] & line[i+1..$]
			i += 1
		elsif c > MAX_SAFE_CHAR or (c < SAFE_CHAR and c != '\t') then -- jjc
			len = length(line)
			line = line[1..i-1] & sprintf("\\x%02x",{c}) & line[i+1..$] -- two digit hex value
			i += (length(line) - len)
		end if
		i += 1
	end while
	return line
end function

sequence chunk
chunk = {}

function add_line(file_number file_no, integer returnLine = FALSE)
-- add a new line to the buffer
	sequence line

	-- begin jjc:
	if length(line_ending[1]) then
		integer f, flag, ch
		flag = -1
		ch = line_ending[1][$]
		while 1 do
			-- trace(1)
			f = find(ch, chunk)
			if wrap_to_screen and length(chunk) > wrap_length then
				if wrap_length < f then
					f = wrap_length
				end if
			end if
			if f then
				line = chunk[1..f] & "\n"
				chunk = chunk[f+1..$]
				exit
			end if
			if flag then
				sequence tmp = myget:get_bytes(file_no, 100) -- has to be 100 for speed with find()
				flag = length(tmp)
				chunk &= tmp
			else
				line = chunk
				chunk = {}
				exit
			end if
		end while
		if length(line) = 0 then -- jjc
			-- end of file
			return FALSE 
		end if
		line = convert_tabs(STANDARD_TAB_WIDTH, edit_tab_width, clean(line))
		--here
	else
		line = myget:get_bytes(file_no, 16) -- read 16 characters at a time
		if length(line) = 0 then -- jjc
			-- end of file
			return FALSE 
		end if
		line = CONTROL_CHAR & pretty_sprint(line, {0,2,1,100,"0x%02x"}) & CONTROL_CHAR & '\n'
	end if

	--line = gets(file_no) -- jjc
	if returnLine then
		return line
	end if
	-- trace(1)
	buffer_append(line)
	--buffer = append(buffer, line)
	-- end jjc.
	return TRUE
end function

procedure new_buffer()
-- make room for a new (empty) buffer
	buffer_list &= 0 -- place holder for new buffer
	buffer_number = length(buffer_list) 
	buffer_make_empty()
	--buffer = {}
end procedure

procedure read_file(file_number file_no)
-- read the entire file into buffer variable
	-- trace(1)
	
	chunk = {}
	-- read and immediately display the first screen-full
	for i = 1 to window_length do
		if not add_line(file_no) then
			exit
		end if
	end for
	DisplayWindow(1, 1)

	-- read the rest
	while add_line(file_no) do
	end while
	chunk = {}

end procedure

procedure set_top_line(sequence message)
-- print message on top line
	set_position(0, 1)
	reverse_video()
	puts(SCREEN, message & BLANK_LINE)
	set_position(0, length(message)+1)
end procedure

procedure arrow_right()
-- action for right arrow key

	sequence tmp
	if b_col < buffer_at_length(b_line) then -- jjc
		tmp = buffer_at(b_line)
		if tmp[b_col] = '\t' then
			s_col = tab(edit_tab_width, s_col)
		else
			s_col += 1
		end if
		b_col += 1
	end if
end procedure

procedure arrow_left()
-- action for left arrow key

	positive_int old_b_col

	old_b_col = b_col
	b_col = 1
	s_col = 1
	for i = 1 to old_b_col - 2 do
		arrow_right()
	end for
end procedure
		
procedure skip_white()
-- set cursor to first non-whitespace in line    
	positive_int temp_col
	
	sequence tmp
	tmp = buffer_at(b_line)
	while find(tmp[b_col], " \t") do
		temp_col = s_col
		arrow_right()
		if s_col = temp_col then
			return -- can't move any further right
		end if
	end while
end procedure

procedure goto_line(integer new_line, integer new_col)
-- move to a specified line and column
-- refresh screen if line is 0
	integer new_s_line
	boolean refresh

	if length_buffer = 0 then
		ClearWindow()
		s_line = 1
		s_col = 1
		return
	end if
	if new_line = 0 then
		new_line = b_line
		refresh = TRUE
	else
		refresh = FALSE
	end if
	if new_line < 1 then
		new_line = 1
	elsif new_line > length_buffer then
		new_line = length_buffer
	end if
	new_s_line = new_line - b_line + s_line
	b_line = new_line
	if not refresh and window_line(new_s_line) then
		-- new line is on the screen
		s_line = new_s_line
	else
		-- new line is off the screen, or refreshing
		s_line = floor((window_length+1)/2)
		if s_line > b_line or length_buffer < window_length then
			s_line = b_line
		elsif b_line > length_buffer - window_length + s_line then
			s_line = window_length - (length_buffer - b_line)
		end if
		DisplayWindow(b_line - s_line + 1, 1)
	end if
	b_col = 1
	s_col = 1
	for i = 1 to new_col-1 do
		arrow_right()
	end for
	set_position(s_line, s_col)
end procedure

function plain_text(char c)
-- defines text for next_word, previous_word 
	return (c >= '0' and c <= '9') or
		   (c >= 'A' and c <= 'Z') or
		   (c >= 'a' and c <= 'z') or
		   c = '_'
end function

procedure next_word()
-- move to start of next word in line
	char c
	positive_int col
	sequence tmp
	
	-- skip plain text
	col = b_col
	tmp = buffer_at(b_line) -- jjc
	while TRUE do
		c = tmp[col]
		if not plain_text(c) then
			exit
		end if
		col += 1
	end while
	
	-- skip white-space and punctuation
	while c != '\n' do
		c = tmp[col]
		if plain_text(c) then
			exit
		end if
		col += 1
	end while
	goto_line(b_line, col)
end procedure

procedure previous_word()
-- move to start of previous word in line    
	char c
	natural col
	sequence tmp
	
	-- skip white-space & punctuation
	col = b_col - 1
	tmp = buffer_at(b_line) -- jjc
	while col > 1 do
		c = tmp[col]
		if plain_text(c) then
			exit
		end if
		col -= 1
	end while

	-- skip plain text
	while col > 1 do
		c = tmp[col-1]
		if not plain_text(c) then
			exit
		end if
		col -= 1
	end while

	goto_line(b_line, col)
end procedure


procedure arrow_up()
-- action for up arrow key
	b_col = 1
	s_col = 1
	if b_line > 1 then
		b_line -= 1
		if s_line > 1 then
			s_line -= 1
		else
			-- move all lines down, display new line at top
			ScrollDown(1, window_length)
			DisplayLine(b_line, 1, TRUE)
			set_position(1, 1)
		end if
		skip_white()
	end if
end procedure

procedure arrow_down()
-- action for down arrow key
	b_col = 1
	s_col = 1
	if b_line < length_buffer then
		b_line += 1
		if s_line < window_length then
			s_line += 1
		else
			-- move all lines up, display new line at bottom
			ScrollUp(1, window_length)
			DisplayLine(b_line, window_length, TRUE)
		end if
		skip_white()
	end if
end procedure


-- begin jjc:
procedure move_text_up()
-- control-down arrow
-- trace(1)
	b_col = 1
	s_col = 1
	if not (s_line = 1 and b_line = length_buffer) then
		if s_line > 1 then
			s_line -= 1
		else
			b_line += 1
		end if
		-- move all lines up, display new line at bottom
		ScrollUp(1, window_length)
		if length_buffer - b_line >= window_length - s_line then
			-- show new line at bottom
			DisplayLine(b_line + window_length - s_line, window_length, TRUE)
		end if
	end if
end procedure

procedure move_text_down()
-- control-up arrow
-- trace(1)
	b_col = 1
	s_col = 1
	if b_line > s_line then
		-- move all lines down, display new line at top
		ScrollDown(1, window_length)
		DisplayLine(b_line - s_line, 1, TRUE)
		if s_line < window_length then
			s_line += 1
		else
			b_line -= 1
		end if
	end if
end procedure
-- end jjc


function numeric(sequence string)
-- convert digit string to an integer
	atom n

	n = 0
	for i = 1 to length(string) do
		if string[i] >= '0' and string[i] <= '9' then
			n = n * 10 + string[i] - '0'
			if not integer(n) then
				return 0
			end if
		else
			exit
		end if
	end for
	return n
end function

function hex_to_bytes(sequence string)
-- convert digit string to an integer
	atom n
	integer status
	sequence bytes
	-- trace(1)
	bytes = {}
	if length(string) = 0 then
		return {GET_EOF, bytes}
	end if
	if and_bits(length(string), 1) then
		string = '0' & string
		status = GET_EOF
	else
		status = GET_SUCCESS
	end if
	for h = 2 to length(string) by 2 do
		n = 0
		for i = h - 1 to h do
			n *= 16
			if string[i] >= '0' and string[i] <= '9' then
				n += string[i] - '0'
			elsif string[i] >= 'a' and string[i] <= 'f' then
				n += string[i] - 'a' + 10
			elsif string[i] >= 'A' and string[i] <= 'F' then
				n += string[i] - 'A' + 10
			else
				return {GET_FAIL, bytes}
			end if
			if not integer(n) or n > 255 or n < 0 then
				return {GET_FAIL, bytes}
			end if
		end for
		bytes = bytes & {n}
	end for
	return {status, bytes}
end function

--here, can insert new functions here.

procedure page_down()
-- action for page-down key
	buffer_line prev_b_line

	if length_buffer <= window_length then
		return
	end if
	prev_b_line = b_line
	b_col = 1
	s_col = 1
	if b_line + window_length + window_length - s_line <= length_buffer then
		b_line = b_line + window_length
	else
		b_line = length_buffer - (window_length - s_line)
	end if
	if b_line != prev_b_line then
		DisplayWindow(b_line - s_line + 1, 1)
	end if
end procedure

procedure page_up()
-- action for page-up key
	buffer_line prev_b_line

	if length_buffer <= window_length then
		return
	end if
	prev_b_line = b_line
	b_col = 1
	s_col = 1
	if b_line - window_length >= s_line then
		b_line = b_line - window_length
	else
		b_line = s_line
	end if
	if b_line != prev_b_line then
		DisplayWindow(b_line - s_line + 1, 1)
	end if
end procedure

procedure set_f_line(natural w, sequence comment)
-- show F-key & file_name
	sequence f_key, text
	
	if length(window_list) = 1 then
		f_key = ""
	else
		f_key = window_name[w] & ' '
	end if
	set_top_line("")
	puts(SCREEN, ' ' & f_key & file_name & comment)
	text = "Esc for commands"
	set_position(0, screen_width - length(text))
	puts(SCREEN, text)
	normal_video()
end procedure

constant W_BUFFER_NUMBER = 1,
	 W_MY_BUFFER_VERSION = 2,
	 W_WINDOW_BASE = 3,
	 W_WINDOW_LENGTH = 4,
	 W_B_LINE = 11

procedure save_state()
-- save current state variables for a window
	window_list[window_number] = {buffer_number, buffer_version, window_base, 
					window_length, auto_complete, multi_color, 
					dot_e, control_chars, cr_removed, file_name, 
					b_line, b_col, s_line, s_col, s_shift, 
					edit_tab_width}
	--here--
	-- possible memory leak.
	-- first, free the buffer, if it exists
	if not atom(buffer_list[buffer_number]) then
		buffer_free(buffer_list[buffer_number][1]) -- possible correction
	end if
	buffer_list[buffer_number] = {buffer_copy(), modified, buffer_version}
end procedure

procedure restore_state(window_id w)
-- restore state variables for a window
	sequence state
	sequence buffer_info

	-- set up new buffer
	state = window_list[w]
	window_number = w
	buffer_number =  state[W_BUFFER_NUMBER]
	buffer_info = buffer_list[buffer_number]
	set_buffer(buffer_info[1])
	modified = buffer_info[2]
	buffer_version = buffer_info[3]
	
	buffer_list[buffer_number] = 0 -- save space
	
	-- restore other variables
	my_buffer_version = state[2]
	window_base = state[3]
	window_length = state[4]
	auto_complete = state[5]
	multi_color = state[6]
	dot_e = state[7]
	control_chars = state[8]
	cr_removed = state[9]
	file_name = state[10]
	edit_tab_width = state[16]
	set_f_line(w, "")

	if buffer_version != my_buffer_version then
		-- buffer has changed since we were last in this window
		-- or window size has changed
		if state[W_B_LINE] > length_buffer then
			if length_buffer = 0 then
				b_line = 1
			else
				b_line = length_buffer
			end if
		else
			b_line = state[W_B_LINE]
		end if
		s_shift = 0
		goto_line(0, 1)
	else
		b_line = state[W_B_LINE]
		b_col = state[12]
		s_line = state[13]
		s_col = state[14]
		s_shift = state[15]
		set_position(s_line, s_col)
	end if
end procedure

procedure refresh_other_windows(positive_int w)
-- redisplay all windows except w
	
	normal_video()
	for i = 1 to length(window_list) do
		if i != w then
			restore_state(i)
			set_f_line(i, "")
			goto_line(0, b_col)
			save_state()
		end if
	end for
end procedure

procedure set_window_size()
-- set sizes for windows
	natural nwindows, lines, base, size
	
	nwindows = length(window_list)
	lines = screen_length - nwindows
	base = 1
	for i = 1 to length(window_list) do
		size = floor(lines / nwindows)
		window_list[i][W_WINDOW_BASE] = base
		window_list[i][W_WINDOW_LENGTH] = size
		window_list[i][W_MY_BUFFER_VERSION] = -1 -- force redisplay
		base += size + 1
		nwindows -= 1
		lines -= size
	end for
end procedure

procedure clone_window()
-- set up a new window that is a clone of the current window
-- save state of current window
	window_id w
	
	if length(window_list) >= MAX_WINDOWS then
		return
	end if
	save_state()
	-- create a place for new window
	window_list = window_list[1..window_number] &
			{window_list[window_number]} &  -- the new clone window
			window_list[window_number+1..$]
	w = window_number + 1
	set_window_size()
	refresh_other_windows(w)
	restore_state(w) 
end procedure

procedure switch_window(integer new_window_number)
-- switch context to a new window on the screen
	
	if new_window_number != window_number then
		save_state()
		restore_state(new_window_number)
	else
		set_f_line(window_number, "") -- is this line necessary? -- jjc
	end if
end procedure

function delete_window()
-- delete the current window    
	boolean buff_in_use
	sequence tmp
	
	window_list = window_list[1..window_number-1] &
				  window_list[window_number+1..$]
	buff_in_use = FALSE
	for i = 1 to length(window_list) do
		if window_list[i][W_BUFFER_NUMBER] = buffer_number then
			buff_in_use = TRUE
			exit
		end if
	end for 
	-- begin jjc:
	-- first, free the buffer, if it exists
	if not atom(buffer_list[buffer_number]) then
		buffer_free(buffer_list[buffer_number][1])
	end if
	if not buff_in_use then
		buffer_list[buffer_number] = 0 -- discard the buffer
	else
		buffer_list[buffer_number] = {buffer_copy(), modified, buffer_version} -- jjc
	end if
	-- end jjc
	if length(window_list) = 0 then
		return TRUE
	end if
	set_window_size()
	refresh_other_windows(1)
	window_number = 1
	restore_state(window_number)
	set_position(s_line, s_col)
	return FALSE
end function

procedure add_queue(sequence keystrokes)
-- add to artificial queue of keystrokes
	key_queue &= keystrokes
end procedure

function next_key()
-- return the next key from the user, or from our 
-- artificial queue of keystrokes. Check for control-c.
	extended_char c
	
	if length(key_queue) then
		-- read next artificial keystroke
		if check_break() then
			key_queue = {}
			--c = CONTROL_C
			c = -(CONTROL_C)
		else
			c = key_queue[1]
			key_queue = key_queue[2..$]
		end if 
	else
		-- read a new keystroke from user
		c = myget:wait_key()
		if check_break() then
			--c = CONTROL_C
			c = -(CONTROL_C)
		end if 

		if c = TAB_KEY then -- jjc
			c = '\t'
		elsif c = NUM_PAD_ENTER then
			c = CR
		elsif c = NUM_PAD_SLASH then
			c = '/'
		elsif c = NUM_PAD_ASTRISK then
			c = '*'
		elsif c = NUM_PAD_PLUS then
			c = '+'
		elsif c = NUM_PAD_MINUS then -- jjc
			c = '-'
		
		elsif c = 296 or c = 282 and ACCENT = 1 then
			-- Discart accent keystroke, and get accented character.
			c = next_key()
		elsif c = ESCAPE then
			-- process escape sequence
			c = get_key()
			if c = -1 then
				return ESCAPE -- it was just the Esc key
			end if
			
			ifdef UNIX then
				-- ANSI codes
				if c = 79 then
					c = myget:wait_key()
					if c = 0 then
						return HOME
					elsif c = 101 then
						return END
					elsif c = 80 then
						return F1
					elsif c = 81 then
						return F1+1 -- F2
					elsif c = 82 then
						return F1+2 -- F3
					elsif c = 83 then
						return F1+3 -- F4
					else
						add_queue({79, c})
					end if

				elsif c = 91 then
					c = get_key()
		
					if c >= 65 and c <= 68 then
						if c = 65 then
							return ARROW_UP
						elsif c = 66 then
							return ARROW_DOWN
						elsif c = 67 then
							return ARROW_RIGHT
						else
							return ARROW_LEFT
						end if
 
					elsif c >= 49 and c <= 54 then
						extended_char c2 = get_key()
						if c = 49 then 
							if c2 = 126 then
								return HOME
							elsif c2 >= 49 and c2 <= 53 then
								if get_key() then --126
								end if
								return F1+c2-49
							elsif c2 >= 55 and c2 <= 57 then
								if get_key() then -- 126
								end if
								return F1+c2-50
							end if
						elsif c = 50 then
							if c2 = 126 then
								return INSERT
							elsif c2 >= 48 and c2 <= 52 then
								if get_key() then -- 126
								end if
								-- F11,F12 are not totally standard
								if c2 = 51 then
									return F11 -- some systems
								elsif c2 = 52 then
									return F12 -- some systems
								else
									return F1+c2-40 -- other systems
								end if
							end if
						elsif c = 51 then
							return DELETE
						elsif c = 52 then
							return END
						elsif c = 53 then
							return PAGE_UP
						elsif c = 54 then
							return PAGE_DOWN
						else
							-- F1..F4 might overlap with the above special keys
							return F1+c-49  
						end if
		
					elsif c = 72 then
						return HOME
		
					elsif c = 70 then
						return END
		
					else -- obsolete?
						c = get_key()
						if get_key() then -- 126
						end if
						add_queue({91, 49, c, 126})
					end if    
				else
					add_queue({c})
				end if
			
			elsedef
				-- DOS/Windows
				if c = 79 then
					c = myget:wait_key()
					if c = 0 then
						return HOME
					elsif c = 101 then
						return END
					else
						add_queue({79, c})
					end if
				
				elsif c = 91 then
					c = get_key() -- 49
					c = get_key()
					if get_key() then -- 126
					end if
					if c >= 49 and c <= 60 then
						return F1+c-49 -- only F1..F4 are like this
					else
						add_queue({91, 49, c, 126})
					end if
				else
					add_queue({c})
				end if
			end ifdef
			
			return ESCAPE
		end if
	end if
	return c
end function

-- function next_key_() -- jjc
--      object key
--      key = next_key()
--      -- trace(1)
--      if recording_macro then
--              macro_buffer &= {key}
--      end if
--      return key
-- end function

procedure refresh_all_windows()
-- redisplay all the windows
	window_id w

	w = window_number
	save_state()
	refresh_other_windows(w)
	restore_state(w)
end procedure

function key_gets(sequence hot_keys, sequence history, integer macro_record = TRUE, integer insert_key = 0) -- jjc
-- Return an input string from the keyboard.
-- Handles special editing keys. 
-- Some keys are "hot" - no Enter required.
-- A list of "history" strings can be supplied,
-- and accessed by the user using up/down arrow.
	sequence input_string
	integer line, init_column, column, char, col, h
	sequence cursor
	boolean first_key
	
	if not HOT_KEYS then
		hot_keys = ""
	end if
	cursor = get_position()
	line = cursor[1]
	init_column = cursor[2]
	history = append(history, "")
	h = length(history)
	if h > 1 then
	   h -= 1  -- start by offering the last choice
	end if
	input_string = history[h]
	column = init_column
	first_key = TRUE
	
	while TRUE do
		position(line, init_column)
		puts(SCREEN, input_string)
		puts(SCREEN, BLANK_LINE)
		position(line, column)
		
		char = next_key() --bookmark--
		if char = INSERT and insert_key then
			char = insert_key
		end if
		if macro_record and sequence(recording_macro) then -- jjc
			-- trace(1)
			macro_buffer &= char
		end if
		
		if char = CR or char = 10 then
			exit
			
		elsif char = BS then
			if column > init_column then
				column -= 1
				col = column-init_column
				input_string = input_string[1..col] &
						input_string[col+2..$]
			end if
		
		elsif char = ARROW_LEFT then
			if column > init_column then
				column -= 1
			end if
		
		elsif char = ARROW_RIGHT then
			if column < init_column+length(input_string) and
			   column < screen_width then
				column += 1
			end if      
		
		elsif char = ARROW_UP then
			if h > 1 then
				h -= 1
			else
				h = length(history)
			end if
			input_string = history[h]
			column = init_column + length(input_string)
		
		elsif char = ARROW_DOWN then
			if h < length(history) then
				h += 1
			else
				h = 1
			end if
			input_string = history[h]
			column = init_column + length(input_string)
			
		elsif char = DELETE or char = XDELETE then
			if column - init_column < length(input_string) then
				col = column-init_column
				input_string = input_string[1..col] &
						input_string[col+2..$]
			end if
		
		elsif char = HOME then
			column = init_column
			
		elsif char = END then
			column = init_column+length(input_string)
				
		elsif (char >= 32 and char <= 255) or char = '\t' then
			-- normal key
			if first_key then
				input_string = ""
			end if
			if column < screen_width then
				if char = '\t' then
					char = ' '
				end if
				column += 1
				if column - init_column > length(input_string) then
					input_string = append(input_string, char)
					if column = init_column + 1 and find(char, hot_keys) then
						exit
					end if
				else
					col = column-init_column
					input_string = input_string[1..col-1] &
							char &
							input_string[col..$]
				end if
			end if
		
		elsif char = -(CONTROL_C) then
			-- refresh screen, treat as Enter key
			refresh_all_windows()
			goto_line(0, b_col)
			input_string &= CR
			exit
		end if
		
		first_key = FALSE
	end while
	
	return input_string
end function

procedure new_screen_length()
-- set new number of lines on screen
	natural nlines
	window_id w
	
	set_top_line("How many lines on screen? (25, 28, 43, 50) ")
	nlines = numeric(key_gets("", {}))
	if nlines then
		screen_length = text_rows(nlines)
		config = video_config() -- jjc
		screen_length = config[VC_SCRNLINES]
		screen_width = config[VC_SCRNCOLS]
		wrap_length = screen_width - length(line_ending[2])
		w = window_number
		save_state()
		set_window_size()
		refresh_other_windows(w)
		restore_state(w)
	end if
end procedure


-- searching/replacing variables
boolean searching, replacing, match_case
searching = FALSE
replacing = FALSE
match_case = TRUE

sequence find_string -- current (default) string to look for
find_string = ""

sequence replace_string -- current (default) string to replace with
replace_string = ""

procedure xreplace()
-- replace find_string by replace_string
-- we are currently positioned at the start of an occurrence of find_string
	sequence line

	set_modified()
	line = buffer_at(b_line) -- jjc
	line = match_replace('\t', line, "\\t") -- jjc
	line = line[1..b_col-1] & replace_string & line[b_col+length(find_string)..$]
	set_buffer_at(b_line, line) -- jjc
	--buffer[b_line] = line -- jjc
	-- position at end of replacement string
	for i = 1 to length(replace_string)-1 do
		arrow_right()
	end for
	DisplayLine(b_line, s_line, FALSE)
end procedure

function alphabetic(object s)
-- does s contain alphabetic characters?
	return find(TRUE, (s >= 'A' and s <= 'Z') or
			  (s >= 'a' and s <= 'z'))
end function

function case_match(sequence string, sequence text)
-- Find string in text with
-- either case-sensitive or non-case-sensitive comparison
	text = match_replace('\t', text, "\\t")
	if match_case then
		return match(string, text)
	else
		return match(lower(string), lower(text))
	end if
end function

function update_history(sequence history, sequence string)
-- update a history variable - string will be placed at the end
	integer f
	
	f = find(string, history) 
	if f then
		-- delete it
		history = history[1..f-1] & history[f+1..$]
	end if
	-- put it at the end
	return append(history, string)
end function

function search(boolean cont)
-- find a string from here to the end of the file
-- return TRUE if string is found
	natural col
	sequence pos, temp_string, tmp
	
	set_top_line("")
	if length_buffer = 0 then
		puts(SCREEN, "buffer empty")
		return FALSE
	end if
	puts(SCREEN, "search for or [INSERT key]: ")
	if cont then
		puts(SCREEN, find_string)
	else
		pos = get_position()
		temp_string = find_string
		find_string = key_gets("", search_history, TRUE, CONTROL_CHAR) -- jjc
		if length(find_string) > 0 then
			if not equal(temp_string, find_string) then
				-- new string typed in
				search_history = update_history(search_history, find_string)
				if alphabetic(find_string) and length(find_string) < 40 then
					set_position(0, pos[2]+length(find_string)+3)
					puts(SCREEN, "match case? n")
					pos = get_position()
					set_position(0, pos[2] - 1)
					match_case = find('y', key_gets("", {}))
				end if
			end if
			if replacing then
				set_top_line("")
				puts(SCREEN, "replace with or [INSERT key]: ")
				replace_string = key_gets("", replace_history, TRUE, CONTROL_CHAR) -- jjc
				replace_history = update_history(replace_history, replace_string)
			end if
		end if
	end if

	normal_video()
	if length(find_string) = 0 then
		return FALSE
	end if
	tmp = buffer_at(b_line) -- jjc
	col = case_match(find_string, tmp[b_col+1..$])
	if col then
		-- found it on this line after current position
		for i = 1 to col do
			arrow_right()
		end for
		if replacing then
			xreplace()
		end if
		return TRUE
	else
		-- check lines following this one
		for b = b_line+1 to length_buffer do
			tmp = buffer_at(b)
			col = case_match(find_string, tmp)
			if col then
				goto_line(b, 1)
				for i = 1 to col - 1 do
				   arrow_right()
				end for
				if replacing then
					xreplace()
				end if
				set_top_line("")
				printf(SCREEN, "searching for: %s", {find_string})
				return TRUE
			end if
		end for
		set_top_line("")
		printf(SCREEN, "\"%s\" not found", {find_string})
		if alphabetic(find_string) then
			if match_case then
				puts(SCREEN, "  (case must match)")
			else
				puts(SCREEN, "  (any case)")
			end if
		end if
	end if
	return FALSE
end function

procedure show_message()
-- display error message from ex.err
	if length(error_message) > 0 then
		set_top_line("")
		puts(SCREEN, error_message)
		normal_video()
	end if
	set_position(s_line, s_col)
end procedure

procedure set_err_pointer()
-- set cursor at point of error 
	
	for i = 1 to screen_width*5 do -- prevents infinite loop
		if s_col >= start_col then
			exit
		end if
		arrow_right()
	end for
end procedure

function delete_trailing_white(sequence name)
-- get rid of blanks, tabs, newlines at end of string
	while length(name) > 0 do
		if find(name[$], "\n\r\t ") then -- jjc, reserved for future versions
			name = name[1..$-1]
		else
			exit
		end if
	end while
	return name
end function

function get_err_line()
-- try to get file name & line number from ex.err
-- returns file_name, sets start_line, start_col, error_message

	file_number err_file
	sequence file_name
	sequence err_lines
	object temp_line
	natural colon_pos

	err_file = open("ex.err", "r")
	if err_file = -1 then
		error_message = ""
	else
		-- read the top of the ex.err error message file
		err_lines = {}
		while length(err_lines) < 6 do
			temp_line = gets(err_file)
			if atom(temp_line) then
				exit
			end if
			err_lines = append(err_lines, temp_line)
		end while
		close(err_file)
		-- look for file name, line, column and error message
		
		if length(err_lines) > 1 and match("TASK ID ", err_lines[1]) then
			err_lines = err_lines[2..$]
		end if
		
		if length(err_lines) > 0 then
			if sequence(err_lines[1]) then
				colon_pos = match(".e", lower(err_lines[1]))
				if colon_pos then
					if find(err_lines[1][colon_pos+2], "xXwWuU") then
						colon_pos += 1
						if find(err_lines[1][colon_pos+2], "wWuU") then
							colon_pos += 1
						end if
					end if
					file_name = err_lines[1][1..colon_pos+1]
					start_line = numeric(err_lines[1][colon_pos+3..length(err_lines[1])])
					error_message = delete_trailing_white(err_lines[2])
					if length(err_lines) > 3 then
						start_col = find('^', expand_tabs(STANDARD_TAB_WIDTH, err_lines[length(err_lines)-1]))
					end if
					return file_name
				end if
			end if
		end if
	end if
	return ""
end function

function last_use()
-- return TRUE if current buffer 
-- is only referenced by the current window
	natural count

	count = 0
	for i = 1 to length(window_list) do
		if window_list[i][W_BUFFER_NUMBER] = buffer_number then
			count += 1
			if count = 2 then
				return FALSE
			end if
		end if
	end for
	return TRUE
end function

procedure save_file(sequence save_name, integer keep = TRUE) -- jjc
-- write buffer to the disk file
	file_number file_no
	--boolean strip_cr
	sequence line, tmp, s, last_line
	integer found, pos
	object ch
	-- begin jjc:
	if file_exists(save_name) then
		set_top_line(sprintf("Backing up %s to %s.bak ", {save_name, save_name}))
		-- if find('y', key_gets("yn", {})) then
			if copy_file(save_name, save_name & ".bak", 1) then
				puts(SCREEN, " ... ok")
			end if
		-- end if
	end if
	set_top_line("")
	file_no = open(save_name, "wb")
	if file_no = -1 then
		printf(SCREEN, "Can't save %s - write permission denied", 
			  {save_name})
		stop = FALSE
		return
	end if
	printf(SCREEN, "saving %s ... ", {save_name})
	start_line = 0
	start_col = 1
	for i = 1 to length_buffer do
		if keep then
			line = buffer_at(i) -- index (i)
		else
			line = buffer_at(1) -- one (1)
			buffer_delete_node_at(1) -- one (1)
			last_line = line
		end if
		line = line[1..$-1]
		s = {}
		pos = 1
		while length(line) do
			ch = line[1]
			line = line[2..$]
			pos += 1
			start_col = pos
			if ch = '\\' then
				-- jjc
				if length(line) = 0 then
					start_line = i
					exit
				end if
				ch = line[1]
				line = line[2..$]
				pos += 1
				start_col = pos
				if ch = 'x' then
					if length(line) < 2 then
						start_line = i
						exit
					end if
					tmp = upper(line[1..2])
					if not t_xdigit(tmp) then
						start_line = i
						exit
					end if
					tmp = value("#" & tmp)
					if tmp[1] = GET_SUCCESS and integer(tmp[2])
						 and tmp[2] <= 255 and tmp[2] >= 0 then -- characers are from 0 to 255
						ch = tmp[2]
						line = line[3..$]
						pos += 2
						start_col = pos
					else
						start_line = i
						exit
					end if
				elsif ch = 't' then
					ch = '\t' -- jjc
				else
					found = find(ch, ESCAPE_CHARS) -- "escape"
					if found then
						ch = ESCAPED_CHARS[found] -- "escaped"
					else
						start_col -= 1 -- get the right offset
						start_line = i
						exit
					end if
				end if
			elsif ch = CONTROL_CHAR then
				found = find(CONTROL_CHAR, line)
				if found then
					if length(line) < 2 then
						start_line = i -- error
						exit
					end if
					if line[1] = '{' or line[1] = '\"' then
						tmp = value(line[1..found-1])
					else
						tmp = hex_to_bytes(line[1..found-1])
					end if
					if tmp[1] = GET_SUCCESS and is_bytes(tmp[2]) then
						ch = tmp[2]
						line = line[found+1..$]
						pos += found
						start_col = pos
					else
						start_line = i
						exit
					end if
				end if
			end if
			if length(s) < APPEND_MIN_SIZE then
				s = s & ch
			else
				s = append(s, ch)
			end if
		end while
		if start_line then
			-- s = s & line
			exit
		end if
-- 		if cr_removed and not strip_cr then
-- 			-- He wants CR's - put them back.
-- 			-- All lines have \n at the end.
-- 			if length(line) < 2 or line[length(line)-1] != '\r' then
-- 				line = line[1..length(line)-1] & "\r\n"
-- 			end if
-- 		end if
		puts(file_no, convert_tabs(edit_tab_width, STANDARD_TAB_WIDTH, s))
	end for
	close(file_no)
-- 	if not strip_cr then
-- 		-- the file doesn't have CR's
-- 		cr_removed = FALSE -- no longer binary
-- 	end if
	if start_line then -- done.
		-- there was a format error in a hexidecimal number.
		-- restore the state of the editor, and display the error.
		if keep = FALSE then
			-- load back what was written, into the memory buffer
			-- wait until this procedure is finished.
			object ob
			buffer_insert_nodes_at(1, {last_line})
			file_no = open(save_name, "rb")
			if file_no = -1 then
				printf(SCREEN, "Can't open %s - read permission denied", 
					  {save_name})
				stop = FALSE
				return
			end if
			pos = 1
			chunk = {}
			while 1 do
				ob = add_line(file_no, TRUE) -- TRUE for string return value.
				if atom(ob) then
					exit
				end if
				buffer_insert_nodes_at(pos, {ob})
				pos += 1
			end while
			chunk = {}
			close(file_no)
		end if
		error_message = sprintf("save error, line=%d, col=%d, try: \\xff hex format", {start_line, start_col})
		show_message()
		goto_line(start_line, 1)
		set_err_pointer()
		stop = FALSE
		return
	else
	-- 	if keep = FALSE then
	-- 		for i = 1 to length_buffer do
	-- 			buffer_delete_node_at(1) -- fastest to start at one (1).
	-- 		end for
	-- 	end if
		puts(SCREEN, "ok")
	end if
	-- end jjc.
	if equal(save_name, file_name) then
		clear_modified() -- modified equals false
	end if
	stop = TRUE
end procedure

procedure shell(sequence command)
-- run an external command
	
	bk_color(BLACK)
	text_color(WHITE)
	clear_screen()
	system(command, 1)
	normal_video()
	while get_key() != -1 do
		-- clear the keyboard buffer
	end while
	refresh_all_windows()
end procedure

procedure first_bold(sequence string)
-- highlight first char
	text_color(TOP_LINE_TEXT_COLOR)
	puts(SCREEN, string[1])
	text_color(TOP_LINE_DIM_COLOR)
	puts(SCREEN, string[2..length(string)])
end procedure

procedure delete_editbuff()
-- Shutting down. Delete EDITBUFF.TMP
	if editbuff then
		system(delete_cmd & TEMPFILE, 2)
	end if
end procedure

constant ids = 
"\t\n\r\\" &
{ESCAPE, CR, NUM_PAD_ENTER, BS, HOME, END, CONTROL_HOME, CONTROL_END,
		PAGE_UP, PAGE_DOWN, INSERT, NUM_PAD_SLASH,
		DELETE, XDELETE, ARROW_LEFT, ARROW_RIGHT,
		CONTROL_ARROW_LEFT, CONTROL_ARROW_RIGHT, ARROW_UP, ARROW_DOWN,
		CONTROL_ARROW_UP, CONTROL_ARROW_DOWN, -- jjc
		CONTROL_DELETE}  -- key for line-delete 
constant names = 
{"\'\\t\'","\'\\n\'","\'\\r\'","\'\\\'"} &
{"ESCAPE", "CR", "NUM_PAD_ENTER", "BS", "HOME", "END", "CONTROL_HOME", "CONTROL_END",
		"PAGE_UP", "PAGE_DOWN", "INSERT", "NUM_PAD_SLASH",
		"DELETE", "XDELETE", "ARROW_LEFT", "ARROW_RIGHT",
		"CONTROL_ARROW_LEFT", "CONTROL_ARROW_RIGHT", "ARROW_UP", "ARROW_DOWN",
		"CONTROL_ARROW_UP", "CONTROL_ARROW_DOWN", -- jjc
		"CONTROL_DELETE"}  -- key for line-delete 

procedure macro_menu() -- jjc
-- process macro menu command
	--object help = FALSE
	
	sequence command, filename, tmp
	--natural line
	--object self_command
	integer fn, num, count

	if first_time = TRUE then
		if db_open(macro_database_filename, DB_LOCK_EXCLUSIVE) != DB_OK then
			if db_create(macro_database_filename, DB_LOCK_EXCLUSIVE) != DB_OK then
				set_top_line(sprintf("Unable to create database \"%s\"", {macro_database_filename}))
				getc(0)
			end if
		end if
		if db_select_table(table_name) != DB_OK then
			if db_create_table(table_name) != DB_OK then
				set_top_line(sprintf("Unable to create table", {table_name}))
				getc(0)
			else
				store_CUSTOM_KEYSTROKES(current_macro, CUSTOM_KEYSTROKES)
			end if
		end if
		set_top_line("Press Enter. " & table_name)
		getc(0)
		set_top_line("When done editing, exit the editor by pressing [ESC] then \'q\'")
		getc(0) -- make the user press Enter.
		first_time = FALSE
	end if

	while 1 do
		-- trace(1)
		cursor(ED_CURSOR)
	
		if sequence(recording_macro) then
			set_top_line(sprintf("%s, RECORDING %s, ", {current_macro, recording_macro}))
		else
			set_top_line(sprintf("%s, READY ", {current_macro}))
		end if
		--if help then
			--command = "h"
		--else
			first_bold("xsave ")
			first_bold("load ")
			first_bold("view ")
			first_bold("record ")
			first_bold("stop ")
			first_bold("name ")
			text_color(TOP_LINE_TEXT_COLOR)
			puts(SCREEN, "CR: ")
			command = key_gets("xlvrsn", {}, FALSE) & ' '
		--end if
	-- trace(1)
		if command[1] = 's' then
			if sequence(recording_macro) then
				-- stop-recording
				-- trace(1)
				if length(macro_buffer) then
					store_CUSTOM_KEYSTROKES(recording_macro, macro_buffer)
					macro_buffer = {}
				end if
				current_macro = recording_macro
				recording_macro = 0
				--set_top_line(sprintf("current macro: %d, STOPPED RECORDING. Use F12 to play back recorded macro. CR ", {macro -  1}))
				--getc(0) -- make the user press Enter.
				--macro_menu()
			end if
		elsif command[1] = 'r' then
			if sequence(recording_macro) then
				-- stop-recording
				-- trace(1)
				if length(macro_buffer) then
					store_CUSTOM_KEYSTROKES(recording_macro, macro_buffer)
					macro_buffer = {}
				end if
				current_macro = recording_macro
				recording_macro = 0
				--set_top_line(sprintf("current macro: %d, STOPPED RECORDING. Use F12 to play back recorded macro. CR ", {macro -  1}))
				--getc(0) -- make the user press Enter.
				--macro_menu()
			else
				-- record macros
				macro_buffer = {}
				recording_macro = current_macro
				--set_top_line(sprintf("current macro: %d, RECORDING, go back to macro menu to stop recording.", {macro -  1}))
				--macro_menu()
			end if
			
		elsif command[1] = 'x' then
			set_top_line("xsave macro file name: ")
			filename = delete_trailing_white(key_gets("", macro_file_history, FALSE))
			if length(filename) != 0 then
				macro_file_history = update_history(macro_file_history, filename)
				fn = open(filename, "w")
				if fn = -1 then
					set_top_line("File does not exist")
					getc(0) -- make the user press Enter.
				else
					puts(fn, "\"" & table_name & "\"\n")
					for i = 1 to db_table_size() do
						printf(fn, "\"%s\"\t", {db_record_key(i)})
						print(fn, db_record_data(i))
						puts(fn, "\n")
					end for
					close(fn)
					set_top_line("done")
				end if
			end if
			
		elsif command[1] = 'l' then
			set_top_line("load macro file name: ")
			filename = delete_trailing_white(key_gets("", macro_file_history, FALSE))
			if length(filename) != 0 then
				macro_file_history = update_history(macro_file_history, filename)
				if atom(dir(filename)) then
					set_top_line(sprintf("File \"%s\" does not exist", {filename}))
					getc(0) -- make the user press Enter.
				else
					fn = open(MACRO_FILE, "w")
					if fn = -1 then
						set_top_line(sprintf("Unable to write to file \"%s\"", {MACRO_FILE}))
						getc(0) -- make the user press Enter.
					else
						puts(fn, "\"" & table_name & "\"\n")
						for i = 1 to db_table_size() do
							printf(fn, "\"%s\"\t", {db_record_key(i)})
							print(fn, db_record_data(i))
							puts(fn, "\n")
						end for
						close(fn)
						set_top_line("done")
					end if
					--else
						--pretty_print(fn, CUSTOM_KEYSTROKES, {3})
						--close(fn)
						--set_top_line("done")
					--end if
					fn = open(filename, "r")
					if fn = -1 then
						set_top_line(sprintf("Unable to read from file \"%s\"", {filename}))
						getc(0) -- make the user press Enter.
					else
						count = 0
						tmp = get(fn) -- first line
						if tmp[1] = GET_SUCCESS and equal(tmp[2], table_name) then
							tmp = get(fn)
							while tmp[1] = GET_SUCCESS do
								if sequence(tmp[2]) then
									filename = tmp[2]
									tmp = get(fn)
									if tmp[1] = GET_SUCCESS and sequence(tmp[2]) then
										store_CUSTOM_KEYSTROKES(filename, tmp[2])
										count += 1
									else
										count = -count
										exit
									end if
								else
									count = -count
									exit
								end if
								tmp = get(fn)
							end while
						else
							if atom(tmp[2]) or not is_bytes(tmp[2]) then
								tmp[2] = "unknown"
							end if
							set_top_line(sprintf("Wrong table version: %s", {tmp[2]}))
							getc(0)
							set_top_line(sprintf("Needs to be: %s", {table_name}))
							getc(0)
						end if
						close(fn)
						if count > 0 then
							set_top_line(sprintf("Loaded all macros: %d loaded", {count}))
						else
							set_top_line(sprintf("Failed to load all macros: %d loaded", {-count}))
						end if
						getc(0) -- make the user press Enter.
						--if tmp[1] = GET_SUCCESS and sequence(tmp[2]) then
							--tmp = tmp[2]
							--for i = 1 to length(tmp) do
								--store_CUSTOM_KEYSTROKES(i - 1, tmp[i])
							--end for
							--set_top_line("done")
						--else
							--set_top_line("Unable to load file")
							--getc(0) -- make the user press Enter.
						--end if
					end if
				end if
			end if
			
		elsif command[1] = 'n' then
			
			-- change current macro, by name
			set_top_line("macro name: ")
			current_macro = delete_trailing_white(key_gets("", macro_name_history, FALSE))
			--if length(current_macro) != 0 then
				macro_name_history = update_history(macro_name_history, current_macro)
			--end if
			macro_repeat = 0
			while macro_repeat < 1 or macro_repeat > 1000 do
				set_top_line(sprintf("has %d keystrokes, playback how many times (1..1000)? ",
					{length(get_CUSTOM_KEYSTROKES(current_macro))}))
				command = key_gets("", {}, FALSE)
				if length(command) then
					if command[1] >= '0' and command[1] <= '9' then
						macro_repeat = numeric(command)
					end if
				else
					macro_repeat = 1
				end if
			end while

		elsif command[1] = 'v' then
			-- view macros
			--example:  ESCAPE,'f',CR,ARROW_RIGHT,BS,'e',ARROW_LEFT
			
			integer f, key
			sequence pos
			
			bk_color(BLACK)
			text_color(WHITE)
			clear_screen()
			--for i = 1 to length do
				
				tmp = get_CUSTOM_KEYSTROKES(current_macro)
				
				printf(1, "Macro #%s: ", {current_macro})
				
				for j = 1 to length(tmp) do
					key = tmp[j]
					f = find(key, ids)
					if f then
						puts(1, names[f])
					elsif key >= SAFE_CHAR and key <= MAX_SAFE_CHAR then
						puts(1, "\'" & key & "\'")
					else
						print(1, key)
					end if
					if j != length(tmp) then
						puts(1, ",")
					end if
					pos = get_position()
					if pos[2] + 20 > screen_width then -- max length is 20 characters
						puts(1, "\n")
						if pos[1] > screen_length then -- only show first 24 lines
							exit
						end if
					end if
				end for
				--if length(CUSTOM_KEYSTROKES[macro]) then
					--pretty_print(1, CUSTOM_KEYSTROKES[macro], {3})
					-- --print(1, CUSTOM_KEYSTROKES[macro])
				--end if
				puts(1, "\n")
			--end for
			myget:wait_key()
			
			normal_video()
			while get_key() != -1 do
				-- clear the keyboard buffer
			end while
			refresh_all_windows()
			
			normal_video()
			goto_line(0, b_col) -- refresh screen
			
			--macro_menu()
			
		else
			set_top_line("")
			if length_buffer = 0 then
				puts(SCREEN, "empty buffer")
			else
				-- begin jjc:
				object tmp1 -- jjc
				integer found
				tmp1 = expand_tabs(edit_tab_width, buffer_at(b_line))
				if tmp1[s_col] = CONTROL_CHAR then
					tmp1 = tmp1[s_col+1..$]
					found = find(CONTROL_CHAR, tmp1)
					if found then
						if tmp1[1] = '{' or tmp1[1] = '\"' then
							tmp = value(tmp1[1..found-1])
						else
							tmp = hex_to_bytes(tmp1[1..found-1])
						end if
						if tmp[1] = GET_SUCCESS then
							if is_bytes(tmp[2]) then
								tmp1 = tmp[2]
								pretty_print(SCREEN,tmp1,{1,0,1,wrap_length,"%d","%.10g",SAFE_CHAR,MAX_SAFE_CHAR,1,0})
							end if
						end if
					end if
				else
					printf(SCREEN, "%s line %d of %d, column %d of %d, ",
						   {file_name, b_line, length_buffer, s_col,
							length(tmp1)-1})
					if modified then
						puts(SCREEN, "modified")
					else
						puts(SCREEN, "not modified")
					end if
					printf(SCREEN, ", character: %d (0x%02x)", {tmp1[s_col], tmp1[s_col]})
				end if
				-- end jjc.
			end if
			exit
		end if
	
	end while

end procedure

procedure get_escape(boolean help)
-- process escape command
	sequence command, answer
	natural line_num
	object self_command

	cursor(ED_CURSOR)

	set_top_line("")
	if help then
		command = "h"
	else
		first_bold("jmod ") -- jjc
		first_bold("b ") -- jjc
		first_bold("pref ") -- jjc, for line endings
		--first_bold("help ")
		first_bold("clone ")
		first_bold("quit ")
		first_bold("save ")
		first_bold("write ")
		first_bold("new ")
		if dot_e then
			first_bold("eui ")
		end if
		first_bold("dos ")
		first_bold("find ")
		first_bold("replace ")
		first_bold("lines ")
		first_bold("mods ")
		first_bold("view ") -- jjc
		text_color(TOP_LINE_TEXT_COLOR)
		--puts(SCREEN, "ddd CR: ")
		command = key_gets("vpbjhcqswnedfrlm", {}) & ' ' -- jjc
	end if

	if command[1] = 'v' then -- view line
		-- jjc:
		sequence line, tmp, s
		integer found
		object ch
		-- view
		bk_color(BLACK)
		text_color(WHITE)
		clear_screen()
		
		line = buffer_at(b_line)
		line = line[b_col..$-1]
		s = {}
		while length(line) do
			ch = line[1]
			line = line[2..$]
			if ch = CONTROL_CHAR then
				found = find(CONTROL_CHAR, line)
				if found then
					if line[1] = '{' or line[1] = '\"' then
						tmp = value(line[1..found-1])
					else
						tmp = hex_to_bytes(line[1..found-1])
					end if
					if tmp[1] = GET_SUCCESS then
						if is_bytes(tmp[2]) then
							ch = tmp[2]
							line = line[found+1..$]
						end if
					end if
				end if
			end if
			s = s & ch
		end while
		
		--pretty_print(SCREEN, s, {2})
		pretty_print(SCREEN, s, {0,2,1,wrap_length,"%d","%.10g",SAFE_CHAR,MAX_SAFE_CHAR,10,1})
		puts(SCREEN, "\n")
		pretty_print(SCREEN, s, {0,2,1,wrap_length,"0x%02x","%.10g",SAFE_CHAR,MAX_SAFE_CHAR,10,1})
		puts(SCREEN, "\n")
		pretty_print(SCREEN, s, {1,2,1,wrap_length,"%d","%.10g",SAFE_CHAR,MAX_SAFE_CHAR,2,1})
		--puts(SCREEN, "\n")
		
		myget:wait_key()
		
		normal_video()
		while get_key() != -1 do
			-- clear the keyboard buffer
		end while
		refresh_all_windows()
		
		normal_video()
		goto_line(0, b_col) -- refresh screen
		
		
	elsif command[1] = 'b' then -- jjc
		set_top_line("insert hexadecimal: 0x")
		command = key_gets("", {})
		-- inserting a sequence of chars
		answer = CONTROL_CHAR & command & CONTROL_CHAR -- default
		command = hex_to_bytes(command)
		if command[1] = GET_SUCCESS then -- special cases
			if length(command[2]) = 1 then -- will not be zero.
				answer = sprintf("\\x%02x", command[2]) -- command[2] length is one (1).
			else
				command = command[2]
				set_top_line("little endian [reversed: 0xabcd to {#cd, #ab}]? ")
				if find('y', key_gets("yn", {})) then
					command = reverse(command)
				end if
				answer = CONTROL_CHAR & "{"
				for i = 1 to length(command) do
					answer = answer & sprintf("0x%02x, ", {command[i]})
				end for
				answer[$-1] = '}'
				answer[$] = CONTROL_CHAR
			end if
		else
			set_top_line("Warning, ")
			if command[1] = GET_EOF then
				puts(SCREEN, "length of hex string is not even (divisible by two).")
			else
				printf(SCREEN, "you may need to edit between control characters (%s).", {CONTROL_CHAR})
			end if
		end if
		normal_video()
		set_modified()
		insert_string(answer)
		return

	elsif command[1] = 'j' then -- jjc
		if sequence(recording_macro) then
			macro_buffer = macro_buffer[1..$-2]
		end if
		macro_menu()
	
	elsif command[1] = 'f' then
		replacing = FALSE
		searching = search(FALSE)

	elsif command[1] = 'r' then
		replacing = TRUE
		searching = search(FALSE)

	elsif command[1] = 'q' then
		if modified and last_use() then
			set_top_line("quit without saving changes? ")
			if find('y', key_gets("yn", {})) then
				stop = delete_window()
			end if
		else
			stop = delete_window()
		end if
	
	elsif command[1] = 'c' then
		clone_window()
		
	elsif command[1] = 'n' then
		set_top_line("new file name: ")
		answer = delete_trailing_white(key_gets("", file_history))
		if length(answer) != 0 then
			stop = TRUE -- new file supplied, so stop is set to TRUE.
			if modified and last_use() then
				while TRUE do
					set_top_line("")
					printf(SCREEN, "save changes to %s? ", {file_name})
					self_command = key_gets("yn", {})
					if find('y', self_command) then
						save_file(file_name, FALSE) -- keep file in memory is FALSE,
						-- because it is modified, it is the last instance, and there is a new file.
						exit
					elsif find('n', self_command) then
						exit
					end if
				end while
			end if
			if stop = TRUE then
				save_state()
				file_name = answer
			end if
		end if
		
	elsif command[1] = 'w' then
		save_file(file_name, TRUE) -- keep file in memory is TRUE
		stop = FALSE

	elsif command[1] = 's' then
		save_file(file_name, FALSE) -- keep file in memory is FALSE
		if stop then
			stop = delete_window()
		end if

	elsif command[1] = 'e' and dot_e then
		if modified then
			save_file(file_name)
			if stop = FALSE then
				normal_video()
				return
			end if
			stop = FALSE
		end if
		-- execute the current file & return
		if sequence(dir("ex.err")) then
			ifdef UNIX then
				system(delete_cmd & "ex.err", 0)
			elsedef
				system(delete_cmd & "ex.err > NUL", 0)
			end ifdef
		end if
		ifdef UNIX then
			shell("eui \"" & file_name & "\"")
		elsedef
			if match(".exw", lower(file_name)) or 
				  match(".ew",  lower(file_name)) then
				shell("euiw \"" & file_name & "\"")
			else
				shell("eui \"" & file_name & "\"")
			end if
		end ifdef
		goto_line(0, b_col)
		if equal(file_name, get_err_line()) then
			goto_line(start_line, 1)
			set_err_pointer()
			show_message()
		end if

	elsif command[1] = 'd' then
		set_top_line("opsys command? ")
		command = key_gets("", command_history)
		if length(delete_trailing_white(command)) > 0 then
			shell(command)
			command_history = update_history(command_history, command)
		end if
		normal_video()
		goto_line(0, b_col) -- refresh screen
	
	elsif command[1] = 'm' then
		-- show differences between buffer and file on disk
		save_file(TEMPFILE)
		if stop then
			stop = FALSE
			shell(compare_cmd & file_name & " " & TEMPFILE & " | more")
			normal_video()
			goto_line(0, b_col)
			editbuff = TRUE
		end if
		
	elsif command[1] = 'h' then
		self_command = getenv("EUDIR")
		if atom(self_command) then
			-- Euphoria hasn't been installed yet 
			set_top_line("EUDIR not set. See installation documentation.")
		else    
			self_command &= SLASH & "docs"
			if help then
				-- trace(1)
				set_top_line(
				"That key does nothing - do you want to view the help text? ")
				answer = key_gets("yn", {}) & ' '
				if answer[1] = 'n' or answer[1] = 'N' then
					set_top_line("")
				else
					answer = "yes"
				end if
			else
				answer = "yes"
			end if
			if answer[1] = 'y' then
				system(self_command & SLASH & "html" & SLASH & "index.html")
			else
				normal_video()
			end if
		end if

	elsif command[1] = 'l' then
		set_top_line("Word wrap to screen, for newly opened files? ")
		answer = key_gets("yn", {}) & ' '
		-- default is "no"
		wrap_to_screen = answer[1] = 'y' or answer[1] = 'Y'
		new_screen_length()

	elsif command[1] >= '0' and command[1] <= '9' then
		line_num = numeric(command)
		normal_video()
		goto_line(line_num, 1)
		if not buffer_line(line_num) then
			set_top_line("")
			printf(SCREEN, "lines are 1..%d", length_buffer)
		end if

	elsif command[1] = 'p' then -- jjc, preferences
		-- change line endings
		set_top_line("Change new line endings to Windows/Linux/Apple or None? [wlan]")
		answer = key_gets("wlan", {}) & ' '
		puts(SCREEN, answer[1] & " OK")
		if answer[1] = 'w' then
			line_ending = WINDOWS_CR
		elsif answer[1] = 'l' then
			line_ending = LINUX_CR
		elsif answer[1] = 'a' then
			line_ending = APPLE_CR
		elsif answer[1] = 'n' then
			line_ending = {"",""} -- binary, no line ending characters (CR is just for displaying the file)
		end if
		set_top_line(sprintf("Line ending: %s", {line_ending[2]})) -- no change in line endings
		wrap_length = screen_width - length(line_ending[2])
		
	else
		set_top_line("")
		if length_buffer = 0 then
			puts(SCREEN, "empty buffer")
		else
			-- begin jjc:
			object tmp1, tmp -- jjc
			integer found
			tmp1 = expand_tabs(edit_tab_width, buffer_at(b_line))
			if tmp1[s_col] = CONTROL_CHAR then
				tmp1 = tmp1[s_col+1..$]
				found = find(CONTROL_CHAR, tmp1)
				if found then
					if tmp1[1] = '{' or tmp1[1] = '\"' then
						tmp = value(tmp1[1..found-1])
					else
						tmp = hex_to_bytes(tmp1[1..found-1])
					end if
					if tmp[1] = GET_SUCCESS then
						if is_bytes(tmp[2]) then
							tmp1 = tmp[2]
							pretty_print(SCREEN,tmp1,{1,0,1,wrap_length,"%d","%.10g",SAFE_CHAR,MAX_SAFE_CHAR,1,0})
						end if
					end if
				end if
			else
				printf(SCREEN, "%s line %d of %d, column %d of %d, ",
					   {file_name, b_line, length_buffer, s_col,
						length(tmp1)-1})
				if modified then
					puts(SCREEN, "modified")
				else
					puts(SCREEN, "not modified")
				end if
				printf(SCREEN, ", character: %d (0x%02x)", {tmp1[s_col], tmp1[s_col]})
			end if
			-- end jjc.
		end if
	end if

	normal_video()
end procedure

procedure xinsert(char key)
-- insert a character into the current line at the current position

	sequence xtail, tmp1

	set_modified()
	tmp1 = buffer_at(b_line)
	xtail = tmp1[b_col..$] -- jjc
	if key = CR or key = '\n' then
		-- truncate this line and create a new line using xtail
		
		tmp1 = buffer_at(b_line) -- jjc
		tmp1 = tmp1[1..b_col-1]
		if key = CR then
			tmp1 &= line_ending[2]
		end if
		set_buffer_at(b_line, tmp1 & '\n') -- jjc
		
		-- keep this:
		buffer_insert_nodes_at(b_line+1, {xtail}) -- jjc
		
-- 		-- old code:
-- 		-- make room for new line:
-- 		buffer = append(buffer, 0)
-- 		for i = length(buffer)-1 to b_line+1 by -1 do
-- 		        buffer[i+1] = buffer[i]
-- 		end for
-- 		-- store new line
-- 		buffer[b_line+1] = xtail
		
		if s_line = window_length then
			arrow_down()
			arrow_up()
		else
			ScrollDown(s_line+1, window_length)
		end if
		if window_length = 1 then
			arrow_down()
		else
			DisplayLine(b_line, s_line, FALSE)
			b_line += 1
			s_line += 1
			DisplayLine(b_line, s_line, FALSE)
		end if
		s_col = 1
		b_col = 1
	else
		if key = '\t' then
			s_col = tab(edit_tab_width, s_col)
		else
			s_col += 1
		end if
		tmp1 = buffer_at(b_line) -- jjc
		set_buffer_at(b_line, tmp1[1..b_col-1] & key & xtail) -- jjc
		
		DisplayLine(b_line, s_line, TRUE)
		b_col += 1
	end if
	set_position(s_line, s_col)
end procedure

procedure insert_string(sequence text)
-- insert a bunch of characters at the current position
	natural save_line, save_col
	sequence ob, tmp
	integer c

	save_line = b_line
	save_col = b_col
	-- trace(1)
	if length_buffer = 0 then -- jjc
		buffer_append("\n")
	end if
	for i = 1 to length(text) do
		if text[i] = CR or text[i] = '\n' then
			xinsert(text[i])
		else
			c = text[i]
			ob = {c} -- jjc
			if c != CONTROL_CHAR then
				--if c < SAFE_CHAR or c > MAX_SAFE_CHAR then -- jjc
				if (c < SAFE_CHAR and c != '\t') or c > MAX_SAFE_CHAR then -- jjc
				--if find(text[i], UNSAFE_CHARS) then -- jjc
					ob = sprintf("\\x%02x",{c})
				end if
			end if
			tmp = buffer_at(b_line)
			tmp = tmp[1..b_col-1] & ob & tmp[b_col..$]
			set_buffer_at(b_line, tmp)
			-- old code:
			--buffer[b_line] = buffer[b_line][1..b_col-1] & ob &
			--                               buffer[b_line][b_col..length(buffer[b_line])]
			b_col += length(ob) -- jjc
			if i = length(text) then
				DisplayLine(b_line, s_line, FALSE)
			end if
		end if
	end for
	goto_line(save_line, save_col)
end procedure

-- expandable words & corresponding text
constant expand_word = {"if", "for", "while", "elsif",
						"procedure", "type", "function"},

		 expand_text = {" then",  "=  to  by  do",  " do",  " then",
						"()",  "()",  "()" 
					   }

procedure try_auto_complete(char key)
-- check for a keyword that can be automatically completed
	sequence word, this_line, white_space, leading_white, begin, tmp
	natural first_non_blank, wordnum

	if key = ' ' then
		xinsert(key)
	end if
	this_line = buffer_at(b_line) -- jjc
	white_space = this_line = ' ' or this_line = '\t'
	first_non_blank = find(0, white_space) -- there's always '\n' at end
	leading_white = this_line[1..first_non_blank - 1]         
	if auto_complete and first_non_blank < b_col - 2 then
		if not find(0, white_space[b_col..length(white_space)-1]) then
			word = this_line[first_non_blank..b_col - 1 - (key = ' ')]
			wordnum = find(word, expand_word)           
			
			if key = CR and equal(word, "else") then
				 leading_white &= '\t'
			
			elsif wordnum > 0 then
				-- expandable word (only word on line)

				begin = expand_text[wordnum] & "\n" & leading_white -- jjc
				
				if equal(word, "elsif") then
					insert_string(begin & '\t')
				   
				elsif find(word, {"function", "type"}) then
					insert_string(begin & "\n" & 
								  leading_white & "\treturn" & "\n" &
								  "end " & expand_word[wordnum])
				else
					insert_string(begin & '\t' & "\n" &
								  leading_white &
								  "end " & expand_word[wordnum])
				end if
			end if
		end if
	end if
	if key = CR then
		if b_col >= first_non_blank then
			-- begin jjc
			tmp = buffer_at(b_line)
			tmp = tmp[1..b_col-1] & leading_white & tmp[b_col..$]
			set_buffer_at(b_line, tmp)
			-- end jjc
			-- old code:
			--buffer[b_line] = buffer[b_line][1..b_col-1] & leading_white &
			--                               buffer[b_line][b_col..length(buffer[b_line])]
			xinsert(CR)
			skip_white()
		else
			xinsert(CR)
		end if
	end if
end procedure

procedure insert_kill_buffer()
-- insert the kill buffer at the current position
-- kill buffer could be a sequence of lines or a sequence of characters

	if length(kill_buffer) = 0 then
		return
	end if
	set_modified()
	if atom(kill_buffer[1]) then
		-- inserting a sequence of chars
		insert_string(kill_buffer)
	else
		-- inserting a sequence of lines
		buffer_insert_nodes_at(b_line, kill_buffer) -- jjc
		-- old code:
		--buffer = buffer[1..b_line - 1] &
		--               kill_buffer &
		--               buffer[b_line..length(buffer)]
		DisplayWindow(b_line, s_line)
		b_col = 1
		s_col = 1
	end if
end procedure

procedure delete_line(buffer_line dead_line)
-- delete a line from the buffer and update the display if necessary

	integer x

	set_modified()
	-- move up all lines coming after the dead line
	buffer_delete_node_at(dead_line) -- jjc
	-- old code:
	--for i = dead_line to length_buffer-1 do
	--      buffer[i] = buffer[i+1]
	--end for
	--buffer = buffer[1..length(buffer)-1]
	
	x = dead_line - b_line + s_line
	if window_line(x) then
		-- dead line is on the screen at line x
		ScrollUp(x, window_length)
		if length_buffer - b_line >= window_length - s_line then
			-- show new line at bottom
			DisplayLine(b_line + window_length - s_line, window_length, TRUE)
		end if
	end if
	if b_line > length_buffer then
		arrow_up()
	else
		b_col = 1
		s_col = 1
	end if
	adding_to_kill = TRUE
end procedure

procedure delete_char()
-- delete the character at the current position
	char dchar
	sequence xhead, tmp, s
	natural save_b_col
-- trace(1)
	set_modified()
	-- begin jjc
	tmp = buffer_at(b_line)
	dchar = tmp[b_col]
	xhead = tmp[1..b_col - 1]
	tmp = tmp[b_col+1..$]
	-- end jjc
	-- old code:
	--dchar = buffer[b_line][b_col]
	--xhead = buffer[b_line][1..b_col - 1]
	if dchar = '\n' then
		if b_line < length_buffer then
			-- join this line with the next one and delete the next one
			-- begin jjc
			s = line_ending[2]
			if length(line_ending[1]) then
				if length(s) < b_col then
					if equal(xhead[$-length(s)+1..$], s) then
						xhead = xhead[1..$-length(s)] -- trim off line ending.
						b_col -= length(s)
					end if
				end if
			end if
			tmp = buffer_at(b_line+1) -- jjc
			set_buffer_at(b_line, xhead & tmp) -- jjc
			-- end jjc
			-- old code:
			--buffer[b_line] = xhead & buffer[b_line+1]
			DisplayLine(b_line, s_line, FALSE)
			save_b_col = b_col
			delete_line(b_line + 1)
			for i = 1 to save_b_col - 1 do
				arrow_right()
			end for
		else
			if buffer_at_length(b_line) = 1 then -- jjc
				delete_line(b_line)
			else
				arrow_left() -- a line must always end with \n
			end if
		end if
	else
		--tmp = buffer_at(b_line) -- jjc
		set_buffer_at(b_line, xhead & tmp) -- jjc
		-- old code:
		--buffer[b_line] = xhead & buffer[b_line][b_col+1..length(buffer[b_line])]
		if buffer_at_length(b_line) = 0 then
			delete_line(b_line)
		else
			DisplayLine(b_line, s_line, FALSE)
			if b_col > buffer_at_length(b_line) then
				arrow_left()
			end if
		end if
	end if
	adding_to_kill = TRUE
end procedure

function good(extended_char key)
-- return TRUE if key should be processed
	if find(key, SPECIAL_KEYS) then
		return TRUE
	elsif key >= ' ' and key <= 255 then
		return TRUE
	elsif key = '\t' or key = CR then
		return TRUE
	else
		return FALSE
	end if
end function

procedure edit_file()
-- edit the file in buffer
	extended_char key
	sequence tmp

	if length_buffer > 0 then
		if start_line > 0 then
			if start_line > length_buffer then
				start_line = length_buffer
			end if
			goto_line(start_line, 1)
			set_err_pointer()
			show_message()
		end if
	end if
	
	-- to speed up keyboard repeat rate:
	-- system("mode con rate=30 delay=2", 2)
	
	cursor(ED_CURSOR)
	stop = FALSE

	while not stop do

		key = next_key() --bookmark--
		if key = (-CONTROL_C) then
			refresh_all_windows()
			goto_line(0, b_col)
		end if
		
		if good(key) then
			-- normal key
			if find(key, ignore_keys) then
				-- ignore
			elsif sequence(recording_macro) then -- jjc
				-- trace(1)
				if length(macro_buffer) < APPEND_MIN_SIZE then
					macro_buffer &= key
				else
					macro_buffer = append(macro_buffer, key)
				end if
			end if
			if key = CUSTOM_KEY then
				if sequence(recording_macro) then
					macro_buffer = macro_buffer[1..$-1]
				end if
				tmp = get_CUSTOM_KEYSTROKES(current_macro)
				for i = 1 to macro_repeat do
					add_queue(tmp)
				end for

			elsif find(key, window_swap_keys) then
				integer next_window = find(key, window_swap_keys)
				if next_window <= length(window_list) then
					switch_window(next_window)
				else
					set_top_line("")
					printf(SCREEN, "F%d is not an active window", next_window)
					normal_video()
				end if
				adding_to_kill = FALSE
				
			elsif length_buffer = 0 and key != ESCAPE then
				-- empty buffer
				-- only allowed action is to insert something
				if key = INSERT or not find(key, SPECIAL_KEYS) then
					-- initialize buffer
					buffer_append("\n") -- one line with \n
					b_line = 1
					b_col = 1
					s_line = 1
					s_col = 1
					if key = INSERT then
						insert_kill_buffer()
					else
						xinsert(key)
					end if
					DisplayLine(1, 1, FALSE)
				end if

			elsif key = DELETE or key = XDELETE then
				tmp = buffer_at(b_line)
				-- trace(1)
				if length(tmp) - b_col = length(line_ending[2]) and
						equal(tmp[$-length(line_ending[2])..$], line_ending[2] & '\n') then
					tmp = line_ending[2] & '\n'
				else
					tmp = {tmp[b_col]}
				end if
				if not adding_to_kill then
					kill_buffer = tmp
				elsif sequence(kill_buffer[1]) then
					-- we were building up deleted lines,
					-- but now we'll switch to chars
					kill_buffer = tmp
				else
					for i = 1 to length(tmp) do
						kill_buffer = append(kill_buffer, tmp[i])
					end for
				end if
				for i = 1 to length(tmp) do
					delete_char()
				end for

			elsif key = CONTROL_DELETE or key = CONTROL_D then
				tmp = buffer_at(b_line)
				if not adding_to_kill then
					kill_buffer = {tmp}
				elsif atom(kill_buffer[1]) then
					-- we were building up deleted chars,
					-- but now we'll switch to lines
					kill_buffer = {tmp}
				else
					kill_buffer = append(kill_buffer, tmp)
				end if
				delete_line(b_line)

			else
				if key = PAGE_DOWN or key = CONTROL_P then
					page_down()

				elsif key = PAGE_UP or key = CONTROL_U then
					page_up()

				elsif key = ARROW_LEFT then
					arrow_left()

				elsif key = ARROW_RIGHT then
					arrow_right()

				elsif key = CONTROL_ARROW_LEFT or key = CONTROL_L then
					previous_word()

				elsif key = CONTROL_ARROW_RIGHT or key = CONTROL_R then
					next_word()

				elsif key = ARROW_UP then
					arrow_up()

				elsif key = ARROW_DOWN then
					arrow_down()

				elsif key = CONTROL_ARROW_UP or key = CONTROL_Y then -- jjc
					move_text_down()

				elsif key = CONTROL_ARROW_DOWN or key = CONTROL_N then -- jjc
					move_text_up()

				elsif key = ' ' then
					try_auto_complete(key)

				elsif key = INSERT then
					insert_kill_buffer()

				elsif key = BS then
					if b_col > 1 then
						arrow_left()
						delete_char()
					elsif b_line > 1 then
						arrow_up()
						goto_line(b_line, buffer_at_length(b_line))
						delete_char()
					end if

				elsif key = HOME then
					b_col = 1
					s_col = 1
				
				elsif key = END then
					-- begin jjc:
					sequence s
					integer len
					len = buffer_at_length(b_line)
					if length(line_ending[1]) then
						s = line_ending[2]
						if length(s) < len then
							tmp = buffer_at(b_line)
							tmp = tmp[$-length(s)..$-1]
							if equal(tmp, s) then
								len = len - length(s)
							end if
						end if
					end if
					goto_line(b_line, len)
					-- end jjc.
				elsif key = CONTROL_HOME or key = CONTROL_T then
					goto_line(1, 1)

				elsif key = CONTROL_END or key = CONTROL_B then
					goto_line(length_buffer, buffer_at_length(length_buffer))

				elsif key = ESCAPE then
					-- special command
					get_escape(FALSE)

				elsif key = CR then
					if searching then
						searching = search(TRUE)
						normal_video()
						searching = TRUE -- avoids accidental <CR> insertion
					else
						try_auto_complete(key)
					end if
				
				elsif find(key, ignore_keys) then
					-- ignore
				
				else
					xinsert(key)

				end if

				adding_to_kill = FALSE

			end if

			if key != CR and key != ESCAPE then
				searching = FALSE
			end if
			cursor(ED_CURSOR)
		
		else
			-- illegal key pressed
			get_escape(TRUE)  -- give him some help
		end if
		set_position(s_line, s_col)
	end while
end procedure

procedure ed(sequence command)
-- editor main procedure 
-- start editing a new file
-- ed.ex is executed by ed.bat
-- command line will be:
--    eui ed.ex              - get filename from ex.err, or user
--    eui ed.ex filename     - filename specified

	file_number file_no

	start_line = 0
	start_col = 0

	if length(command) >= 3 then
		ifdef UNIX then
			file_name = command[3]
		elsedef
			file_name = lower(command[3])
		end ifdef
	else
		file_name = get_err_line()
	end if
	graphics:wrap(0)
	if length(file_name) = 0 then
		-- we still don't know the file name - so ask user
		puts(SCREEN, "file name: ")
		cursor(ED_CURSOR)
		file_name = key_gets("", file_history)
		puts(SCREEN, '\n')
	end if
	file_name = delete_trailing_white(file_name)
	if length(file_name) = 0 then
		buffer_make_empty()
		abort(1) -- file_name was just whitespace - quit
	end if
	file_history = update_history(file_history, file_name)
	file_no = open(file_name, "rb") -- jjc

	-- turn off multi_color & auto_complete for non .e files
	multi_color = WANT_COLOR_SYNTAX
	auto_complete = WANT_AUTO_COMPLETE
	if not config[VC_COLOR] or config[VC_MODE] = 7 then
		multi_color = FALSE -- mono monitor
	end if
	file_name &= ' '
	dot_e = FALSE
	for i = 1 to length(E_FILES) do
		if match(E_FILES[i] & ' ', file_name) then
			dot_e = TRUE
		end if
	end for
	if not dot_e then
		multi_color = FALSE
		auto_complete = FALSE
	end if
	
	-- use PROG_INDENT tab width for Euphoria & other languages:
	edit_tab_width = STANDARD_TAB_WIDTH
	for i = 1 to length(PROG_FILES) do
	   if match(PROG_FILES[i] & ' ', file_name) then
		   edit_tab_width = PROG_INDENT
		   exit
	   end if
	end for
	
	if multi_color then
		init_class()
		set_colors({
				{"NORMAL", NORMAL_COLOR},
				{"COMMENT", COMMENT_COLOR},
				{"KEYWORD", KEYWORD_COLOR},
				{"BUILTIN", BUILTIN_COLOR},
				{"STRING", STRING_COLOR},
				{"BRACKET", BRACKET_COLOR}})    
	end if

	file_name = file_name[1..$-1] -- remove ' '
	adding_to_kill = FALSE
	clear_modified()
	buffer_version = 0
	control_chars = FALSE -- reserved -- jjc
	cr_removed = FALSE -- reserved -- jjc
	new_buffer() -- jjc
	s_line = 1
	s_col = 1
	b_line = 1
	b_col = 1
	save_state()
	while get_key() != -1 do
		-- clear the keyboard buffer 
		-- to reduce "key bounce" problems
	end while
	if file_no = -1 then
		set_f_line(window_number, " <new file>")
		ClearWindow()
	else
		set_f_line(window_number, "")
		set_position(1, 1)
		cursor(NO_CURSOR)
		read_file(file_no)
		close(file_no)
	end if
	set_position(1, 1)
	edit_file()
end procedure

procedure ed_main()
-- startup and shutdown of ed()
	sequence cl

	allow_break(FALSE)
	
	config = video_config()
	if config[VC_XPIXELS] > 0 then
		config = video_config()
	end if

	if config[VC_SCRNLINES] != INITIAL_LINES then
		screen_length = text_rows(INITIAL_LINES)
		config = video_config()
	end if
	screen_length = config[VC_SCRNLINES]
	screen_width = config[VC_SCRNCOLS]
	wrap_length = screen_width - length(line_ending[2])

	BLANK_LINE = repeat(' ', screen_width)
	window_length = screen_length - 1

	cl = command_line()

	while length(window_list) > 0 do
		ed(cl)
		cl = {"eui", "ed.ex" , file_name}
	end while

	-- exit editor
	buffer_make_empty() -- jjc
	delete_editbuff()
	if screen_length != FINAL_LINES then
		screen_length = text_rows(FINAL_LINES)
	end if
	
if 0 then
	cursor(UNDERLINE_CURSOR)
	bk_color(BLACK)
	text_color(WHITE)
	position(screen_length, 1)
	puts(SCREEN, BLANK_LINE)
	position(screen_length, 1)
	puts(SCREEN, "\n")
end if
	
	clear_screen()
	ifdef UNIX then
		free_console()
	end ifdef
end procedure

ed_main()
if first_time = FALSE then
	if db_compress() != DB_OK then
		-- wasn't able to compress database file
	end if
	db_close() -- jjc
end if

-- This abort statement reduces the chance of 
-- a syntax error when you edit ed.ex using itself: 
abort(0) 

