-- Metadaten und Registrierung für Aegisub
script_name = "Automatischer Zeilenumbruch V2 (Korrigiert 3)"
script_description = "Setzt Zeilenumbrüche nach ca. 30 sichtbaren Zeichen, erhält Wörter und ignoriert Tags für die Zählung."
script_author = "Gemini (mit Anpassungen & Korrektur)"
script_version = "1.6"

-- Benötigt für korrekte UTF-8 Zeichenlängenberechnung
local unicode_module_loaded, unicode = pcall(require, "unicode")
if not unicode_module_loaded then
    unicode = {} 
end

local utf8_lib = _G.utf8
local MAX_CHARS_PER_LINE = 30

function get_utf8_true_length(str)
    if type(str) ~= "string" then return 0 end
    if unicode and unicode.utf8_len then
        local success, length = pcall(unicode.utf8_len, str)
        if success and type(length) == "number" then return length end
    end
    if unicode and unicode.len then
        local success, length = pcall(unicode.len, str)
        if success and type(length) == "number" then return length end
    end
    if utf8_lib and utf8_lib.len then
        local success, length = pcall(utf8_lib.len, str)
        if success and type(length) == "number" then return length end
    end
    return #str
end

function get_visible_text_and_length(text_segment)
    if text_segment == nil then return "", 0 end
    local clean_text = text_segment:gsub("{\\[^}]*}", "")
    return clean_text, get_utf8_true_length(clean_text)
end

function tokenize_into_text_and_tags(original_text)
    local tokens = {}
    local i = 1
    while i <= #original_text do
        local tag_start, tag_end = original_text:find("{\\[^}]*}", i)
        if tag_start == i then
            table.insert(tokens, { type = "tag", value = original_text:sub(i, tag_end) })
            i = tag_end + 1
        else
            local text_segment_end
            if tag_start then
                text_segment_end = tag_start - 1
            else
                text_segment_end = #original_text
            end
            local text_value = original_text:sub(i, text_segment_end)
            if #text_value > 0 then
                table.insert(tokens, { type = "text", value = text_value })
            end
            i = text_segment_end + 1
        end
    end
    return tokens
end

function process_subtitle_line(subs, line_index)
    local line = subs[line_index]
    if not line or line.class ~= "dialogue" then return end

    local original_text = line.text
    local _, total_visible_length = get_visible_text_and_length(original_text)

    if total_visible_length <= MAX_CHARS_PER_LINE then
        return
    end

    local tokens = tokenize_into_text_and_tags(original_text)
    local result_text_parts = {}

    local current_line_raw_segments = {}
    local current_line_visible_count = 0
    local last_potential_break = nil

    for _, token in ipairs(tokens) do
        if token.type == "tag" then
            table.insert(current_line_raw_segments, token.value)
        else -- token.type == "text"
            local text_content = token.value
            local current_pos_in_text_content = 1
            
            while current_pos_in_text_content <= #text_content do
                local current_space_segment = ""
                local current_word_segment = nil -- Explizit als nil initialisieren

                -- 1. Führende Leerzeichen vom current_pos_in_text_content konsumieren
                local matched_spaces = text_content:match("^%s*", current_pos_in_text_content)
                if type(matched_spaces) == "string" and #matched_spaces > 0 then
                    current_space_segment = matched_spaces
                    current_pos_in_text_content = current_pos_in_text_content + #current_space_segment
                end

                -- 2. Wort vom current_pos_in_text_content (nach Leerzeichen) konsumieren
                if current_pos_in_text_content <= #text_content then
                    local matched_word = text_content:match("^[^%s]+", current_pos_in_text_content)
                    if type(matched_word) == "string" then -- string.match gibt einen String zurück, wenn gefunden
                        current_word_segment = matched_word
                        -- Die folgende Zeile (oder eine ähnliche) war der Fehlerpunkt, wenn current_word_segment nil war.
                        -- Durch die Prüfung 'if type(matched_word) == "string"' ist #current_word_segment hier sicher.
                        current_pos_in_text_content = current_pos_in_text_content + #current_word_segment
                    end
                end
                
                -- Sicherheitsprüfung: Wenn in dieser Iteration nichts konsumiert wurde, Schleife verlassen oder Zeiger erhöhen
                if #current_space_segment == 0 and current_word_segment == nil then
                    if current_pos_in_text_content <= #text_content then
                        -- Dies sollte nicht passieren, wenn die Muster alle Zeichen abdecken.
                        -- Als Notfallmaßnahme, um eine Endlosschleife zu verhindern:
                        -- aegisub.log(2, "Warnung: Innerer Text-Parser-Loop bei Pos " .. current_pos_in_text_content .. " festgefahren. Text: '" .. text_content:sub(current_pos_in_text_content, current_pos_in_text_content + 10) .. "'. Breche ab.\n")
                        current_pos_in_text_content = #text_content + 1 -- Erzwinge Schleifenende
                    else
                        -- current_pos_in_text_content ist bereits > #text_content, die Schleife wird normal enden.
                        break 
                    end
                end

                -- Verarbeite das extrahierte current_space_segment (immer String) und current_word_segment (String oder nil)
                if #current_space_segment > 0 then
                    table.insert(current_line_raw_segments, current_space_segment)
                    last_potential_break = {
                        raw_segment_count = #current_line_raw_segments,
                        visible_chars = current_line_visible_count 
                    }
                end

                if current_word_segment then -- Nur ausführen, wenn current_word_segment NICHT nil ist
                    local word_visible_length = get_utf8_true_length(current_word_segment)
                    local projected_length = current_line_visible_count + word_visible_length
                    
                    if current_line_visible_count > 0 and projected_length > MAX_CHARS_PER_LINE then
                        if last_potential_break and last_potential_break.visible_chars > 0 then
                            local break_at_raw_index = last_potential_break.raw_segment_count
                            for i = 1, break_at_raw_index do table.insert(result_text_parts, table.remove(current_line_raw_segments, 1)) end
                            if #result_text_parts > 0 and result_text_parts[#result_text_parts]:match("%s+$") then
                                result_text_parts[#result_text_parts] = result_text_parts[#result_text_parts]:match("^(.-)%s*$")
                                if #result_text_parts[#result_text_parts] == 0 then table.remove(result_text_parts) end
                            end
                            if #result_text_parts > 0 then
                                local L = "" ; for k = #result_text_parts, 1, -1 do if result_text_parts[k] ~= "\\N" then L = result_text_parts[k]; break; end end
                                local vis_L_text, _ = get_visible_text_and_length(L); if #vis_L_text > 0 then table.insert(result_text_parts, "\\N") end
                            end
                            current_line_visible_count = 0
                            for _, sv in ipairs(current_line_raw_segments) do local _, l = get_visible_text_and_length(sv); current_line_visible_count = current_line_visible_count + l; end
                            last_potential_break = nil
                            table.insert(current_line_raw_segments, current_word_segment)
                            current_line_visible_count = current_line_visible_count + word_visible_length
                        else
                            if #current_line_raw_segments > 0 then
                                for _, rs in ipairs(current_line_raw_segments) do table.insert(result_text_parts, rs) end
                                if #result_text_parts > 0 and result_text_parts[#result_text_parts]:match("%s+$") then
                                   result_text_parts[#result_text_parts] = result_text_parts[#result_text_parts]:match("^(.-)%s*$")
                                   if #result_text_parts[#result_text_parts] == 0 then table.remove(result_text_parts) end
                                end
                                if #result_text_parts > 0 then
                                     local L = "" ; for k = #result_text_parts, 1, -1 do if result_text_parts[k] ~= "\\N" then L = result_text_parts[k]; break; end end
                                     local vis_L_text, _ = get_visible_text_and_length(L); if #vis_L_text > 0 then table.insert(result_text_parts, "\\N") end
                                end
                                current_line_raw_segments = {}
                                current_line_visible_count = 0
                            end
                            table.insert(current_line_raw_segments, current_word_segment)
                            current_line_visible_count = word_visible_length
                            last_potential_break = nil
                        end
                    else
                        table.insert(current_line_raw_segments, current_word_segment)
                        current_line_visible_count = current_line_visible_count + word_visible_length
                    end
                end -- Ende if current_word_segment
            end -- Ende while current_pos_in_text_content
        end -- Ende if token.type
    end -- Ende for ipairs(tokens)

    for _, raw_segment in ipairs(current_line_raw_segments) do
        table.insert(result_text_parts, raw_segment)
    end
    if #result_text_parts > 0 and type(result_text_parts[#result_text_parts]) == "string" and result_text_parts[#result_text_parts]:match("%s+$") then
       result_text_parts[#result_text_parts] = result_text_parts[#result_text_parts]:match("^(.-)%s*$")
       if #result_text_parts[#result_text_parts] == 0 then table.remove(result_text_parts) end
    end

    local final_text_output_build = {}
    local previous_part_was_N = true 
    for _, part_val_str in ipairs(result_text_parts) do
        if part_val_str == "\\N" then
            if not previous_part_was_N then
                table.insert(final_text_output_build, part_val_str)
                previous_part_was_N = true
            end
        elseif type(part_val_str) == "string" and #part_val_str > 0 then
            local current_part_to_add = part_val_str
            if previous_part_was_N then 
                current_part_to_add = current_part_to_add:match("^%s*(.*)")
            end
            if #current_part_to_add > 0 then
                 table.insert(final_text_output_build, current_part_to_add)
                 previous_part_was_N = false
            elseif #final_text_output_build > 0 and final_text_output_build[#final_text_output_build] == "\\N" then
                previous_part_was_N = true 
            end
        elseif type(part_val_str) == "string" and #part_val_str == 0 then
            -- Leere Strings ignorieren, es sei denn, sie sind explizit Teil der Logik (hier nicht der Fall)
        else 
             table.insert(final_text_output_build, part_val_str) 
             previous_part_was_N = false
        end
    end

    if #final_text_output_build > 0 and final_text_output_build[#final_text_output_build] == "\\N" then
        table.remove(final_text_output_build)
    end
    
    if #final_text_output_build > 0 or (total_visible_length == 0 and not original_text:find("%S")) then
        line.text = table.concat(final_text_output_build)
    elseif #final_text_output_build == 0 and total_visible_length > 0 then
        line.text = original_text 
        -- aegisub.log(2, "Hinweis: Zeilenumbruch führte zu leerem Text für Zeile: '" .. original_text .. "'. Original beibehalten.\n")
    end

    subs[line_index] = line
end

function apply_auto_line_breaks(subs, selected_ids)
    aegisub.progress.title(script_name .. " wird ausgeführt...")
    aegisub.progress.set(0) 

    for i = 1, #selected_ids do
        process_subtitle_line(subs, selected_ids[i])
        aegisub.progress.set(i / #selected_ids * 100) 
        if aegisub.progress.is_cancelled() then
            break 
        end
    end

    aegisub.set_undo_point(script_name) 
    return selected_ids 
end

aegisub.register_macro(script_name, script_description, apply_auto_line_breaks)