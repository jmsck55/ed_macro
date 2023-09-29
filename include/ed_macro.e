-- ed_macro.e is a file for ed_macro_mod, a recordable macro version of ed.ex
-- Copyright James Cook All Rights Reserved
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
-- 
-- You can contact me online using my email address: jmsck55@gmail.com
-- 
------------------------------------------------------------------------------
-- Code begins:
--
-- Steps to take when modifying ed.ex:
--
-- Step 1: comment out 'constant CUSTOM_KEYSTROKES = HOME & "-- " & ARROW_DOWN'
-- Step 2: add "sequence CUSTOM_KEYSTROKES" below it.
-- Step 3: add 'CUSTOM_KEYSTROKES = HOME & "-- " & ARROW_DOWN' below that.
-- Step 4: add "integer recording_macro" and "sequence macro" to below it.
-- Step 5: add "recording_macro = 0" and "macro = {}" below that.
-- Step 6: declare variables used in the macro menu:
-- macro_history = {}, macros = {{},{}}
-- Step 7: change:
--	    -- normal key
-- 
--	    if key = CUSTOM_KEY then
--	        add_queue(CUSTOM_KEYSTROKES)
-- to:
--	    -- normal key
-- 
--	    if recording_macro = 1 then
--          if key != CUSTOM_KEY then
--              macro &= {key}
--          end if
--	    end if
--	    if key = CUSTOM_KEY then
--    	    add_queue(CUSTOM_KEYSTROKES)
-- Step 8: change:
--          command = key_gets("hcqswnedfrlm", {}) & ' '
--      end if
-- 
--      if command[1] = 'f' then
-- to:
--          command = key_gets("jhcqswnedfrlm", {}) & ' '
--      end if
-- 
--      if command[1] = 'j' then
--          ed_macro_menu()
-- 
--      elsif command[1] = 'f' then
-- Step 9:
-- change:
--      first_bold("help ")
-- to:
--      first_bold("jmod ")
-- Step 10: key_gets()
-- change:
--      char = next_key()
-- 
--      if char = CR or char = 10 then
--          exit
-- to:
--      char = next_key()
--      if recording_macro = 1 then
--          macro &= {char}
--      end if
-- 
--      if char = CR or char = 10 then
--          exit
-- Step 11: insert the ed_macro_menu() procedure, before "procedure get_escape(boolean help)"
-- ed_macro_menu() procedure:
procedure ed_macro_menu()
    --done, for now.
    sequence command, answer
    object self_command
    if recording_macro then
        if recording_macro = 1 then
            macro = macro[1..$ - 2]
            recording_macro = 3 -- in macro menu
        end if
        set_top_line("Finish recording new macro [press enter to skip]? ")
        if find('y', key_gets("yn", {})) then
            -- set it to default macro
            recording_macro = 2
            CUSTOM_KEYSTROKES = macro
        end if
    else
        set_top_line("Record new macro [press enter to skip]? ")
        if find('y', key_gets("yn", {})) then
            -- record new macro
            recording_macro = 1
            macro = {}
            set_top_line("RECORDING KEYSTROKES: Press ESC, then \'j\', when done.")
            return
        end if
    end if
    set_top_line("Macro name or [enter]: ")
    macro_history = update_history(macro_history, "")
    command = key_gets("", macro_history)
    if length(command) then
        -- does macro already exist?
        self_command = find(command, macros[1])
        if recording_macro = 2 then
            -- replace macro
            set_top_line("Replace macro \'" & command & "\'? ")
            if find('y', key_gets("yn", {})) then
                if self_command then
                    -- replace
                    macros[2][self_command] = macro
                else
                    -- add to top of the list
                    macros[1] = {command} & macros[1]
                    macros[2] = {macro} & macros[2]
                end if
                recording_macro = 0
                macro = {}
            end if
        else
            if self_command then
                -- macro already exists, make the current macro
                CUSTOM_KEYSTROKES = macros[2][self_command]
            else
                set_top_line("No macro \'" & command & "\'")
            end if
        end if
        macro_history = update_history(macro_history, command)
    else
        set_top_line("Export macros [press enter to skip]? ")
        if find('y', key_gets("yn", {})) then
            self_command = open("ed_macro.txt", "w")
            if self_command = -1 then
                set_top_line("Can\'t export macros.  Unable to open \"ed_macro.txt\"")
            else
                answer = repeat(0, length(macros[1]))
                for i = 1 to length(answer) do
                    answer[i] = {macros[1][i], macros[2][i]}
                end for
                pretty_print(self_command, answer, {3})
                answer = {}
                close(self_command)
                set_top_line("Saved macro information to \"ed_macro.txt\"")
                if recording_macro != 1 then
                    self_command = "ed_macro.txt"
                    if HOT_KEYS then
                        self_command = {ESCAPE, 'c', ESCAPE, 'n'} & self_command 
                    else
                        self_command = {ESCAPE, 'c', '\n', ESCAPE, 'n', '\n'} & self_command 
                    end if
                    add_queue(self_command & CR)
                end if
            end if
        else
            set_top_line("Import macros from \"ed_macro.txt\" [press enter to skip]? ")
            if find('y', key_gets("yn", {})) then
                self_command = open("ed_macro.txt", "r")
                if self_command = -1 then
                    set_top_line("Can\'t import macros.  Unable to open \"ed_macro.txt\"")
                else
                    answer = get(self_command)
                    close(self_command)
                    if answer[1] = GET_SUCCESS then
                        answer = answer[2]
                        for i = 1 to length(answer) do
                            self_command = find(answer[i][1], macros[1])
                            if self_command then
                                macros[2][self_command] = answer[i][2]
                            else
                                macros[1] = append(macros[1], answer[i][1])
                                macros[2] = append(macros[2], answer[i][2])
                            end if
                        end for
                        set_top_line(sprintf("Successfully imported %d macros", {length(answer)}))
                    else
                        set_top_line("Couldn\'t import macros, wrong format.")
                    end if
                    answer = {}
                end if
            end if
        end if
    end if
    if recording_macro = 3 then -- in macro menu.
        recording_macro = 1 -- continue recording.
    end if
end procedure
-- Step 12: In Euphoria v4.0 or higher, add: "include std/pretty.e" to list of include statements.
--here, work on other features later.

-- procedure add_queue(sequence keystrokes)
-- -- add to artificial queue of keystrokes
--     key_queue &= keystrokes
-- end procedure
-- 
-- function next_key()
--     -- return the next key from the user, or from our 
--     -- artificial queue of keystrokes. Check for control-c.

-- function key_gets(sequence hot_keys, sequence history)
--     -- Return an input string from the keyboard.
--     -- Handles special editing keys. 
--     -- Some keys are "hot" - no Enter required.
--     -- A list of "history" strings can be supplied,
--     -- and accessed by the user using up/down arrow.

-- procedure get_escape(boolean help)
--     -- process escape command

-- procedure edit_file()
--     -- edit the file in buffer

