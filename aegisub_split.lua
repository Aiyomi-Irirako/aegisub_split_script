-- Metadata and Registration for Aegisub
script_name = "Automatic Line Break V1.9"
script_description = "Adds line breaks after approx. 30 visible characters, preserves words, ignores tags for counting, and skips lines with existing '\\N'."
script_author = "Unknown"
script_version = "1.9"

-- Required for correct UTF-8 character length calculation
local unicode_module_loaded, unicode = pcall(require, "unicode")
if not unicode_module_loaded then
    -- Optional: Log message if the module could not be loaded.
    -- aegisub.log(2, "Warning: Aegisub 'unicode' module not found. UTF-8 length accuracy may be affected.\n")
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
    -- aegisub.log(2, "Warning: No UTF-8 length function found. Using byte length for character counting (may be inaccurate).\n")
    return #str
end

function get_visible_text_and_length(text_segment)
    if text_segment == nil then return "", 0 end
    local clean_text_val = text_segment:gsub("{\\[^}]*}", "")
    if type(clean_text_val) ~= "string" then
        -- Fallback if gsub unexpectedly does not return a string
        -- aegisub.log(2, "Warning: gsub in get_visible_text_and_length did not return a string for text_segment: '" .. tostring(text_segment) .. "'. Got: " .. type(clean_text_val) .. "\n")
        clean_text_val = "" 
    end
    return clean_text_val, get_utf8_true_length(clean_text_val)
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

    -- NEW CHECK: If the line already contains a manual break, ignore it.
    if original_text:find("\\N", 1, true) then 
        -- The 'true' argument in string.find disables pattern matching (plain find).
        -- aegisub.log(0, "Info: Line with index " .. line_index .. " already contains '\\N' and will be skipped.\n") -- Optional: Log output
        return -- Exit the function for this line, no changes
    end

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
            if type(text_content) ~= "string" then text_content = "" end -- Safety check
            local current_pos_in_text_content = 1
            
            while current_pos_in_text_content <= #text_content do
                local consumed_something_this_iteration = false
                local current_space_segment_for_iteration = ""
                local current_word_segment_for_iteration = nil

                -- 1. Consume leading spaces from current_pos_in_text_content
                local matched_spaces = text_content:match("^%s*", current_pos_in_text_content)
                if type(matched_spaces) ~= "string" then matched_spaces = "" end -- Defensive programming
                
                if #matched_spaces > 0 then
                    current_space_segment_for_iteration = matched_spaces
                    current_pos_in_text_content = current_pos_in_text_content + #matched_spaces 
                    consumed_something_this_iteration = true
                end

                -- 2. Consume word from current_pos_in_text_content (after spaces)
                if current_pos_in_text_content <= #text_content then
                    local matched_word = text_content:match("^[^%s]+", current_pos_in_text_content)
                    if type(matched_word) == "string" then 
                        current_word_segment_for_iteration = matched_word
                        current_pos_in_text_content = current_pos_in_text_content + #current_word_segment_for_iteration 
                        consumed_something_this_iteration = true
                    end
                end
                
                -- Process the extracted current_space_segment_for_iteration and current_word_segment_for_iteration
                if #current_space_segment_for_iteration > 0 then
                    table.insert(current_line_raw_segments, current_space_segment_for_iteration)
                    last_potential_break = {
                        raw_segment_count = #current_line_raw_segments,
                        visible_chars = current_line_visible_count 
                    }
                end

                if current_word_segment_for_iteration then 
                    local word_visible_length = get_utf8_true_length(current_word_segment_for_iteration)
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
                                local L_content = "" 
                                for k = #result_text_parts, 1, -1 do 
                                    if result_text_parts[k] == "\\N" then break end 
                                    if type(result_text_parts[k]) == "string" then L_content = result_text_parts[k] .. L_content else L_content = tostring(result_text_parts[k]) .. L_content end
                                end
                                local vis_L_text, _ = get_visible_text_and_length(L_content); if type(vis_L_text) == "string" and #vis_L_text > 0 then table.insert(result_text_parts, "\\N") end
                            end
                            current_line_visible_count = 0
                            for _, sv in ipairs(current_line_raw_segments) do local _, l = get_visible_text_and_length(sv); current_line_visible_count = current_line_visible_count + l; end
                            last_potential_break = nil
                            table.insert(current_line_raw_segments, current_word_segment_for_iteration)
                            current_line_visible_count = current_line_visible_count + word_visible_length
                        else
                            if #current_line_raw_segments > 0 then
                                for _, rs in ipairs(current_line_raw_segments) do table.insert(result_text_parts, rs) end
                                if #result_text_parts > 0 and result_text_parts[#result_text_parts]:match("%s+$") then
                                   result_text_parts[#result_text_parts] = result_text_parts[#result_text_parts]:match("^(.-)%s*$")
                                   if #result_text_parts[#result_text_parts] == 0 then table.remove(result_text_parts) end
                                end
                                if #result_text_parts > 0 then
                                     local L_content = "" 
                                     for k = #result_text_parts, 1, -1 do 
                                         if result_text_parts[k] == "\\N" then break end 
                                         if type(result_text_parts[k]) == "string" then L_content = result_text_parts[k] .. L_content else L_content = tostring(result_text_parts[k]) .. L_content end
                                     end
                                     local vis_L_text, _ = get_visible_text_and_length(L_content); if type(vis_L_text) == "string" and #vis_L_text > 0 then table.insert(result_text_parts, "\\N") end
                                end
                                current_line_raw_segments = {}
                                current_line_visible_count = 0
                            end
                            table.insert(current_line_raw_segments, current_word_segment_for_iteration)
                            current_line_visible_count = word_visible_length
                            last_potential_break = nil
                        end
                    else
                        table.insert(current_line_raw_segments, current_word_segment_for_iteration)
                        current_line_visible_count = current_line_visible_count + word_visible_length
                    end
                end 
                
                if not consumed_something_this_iteration then
                    -- If nothing was consumed (neither space nor word),
                    -- and we are not at the end, exit loop to prevent infinite loop.
                    if current_pos_in_text_content <= #text_content then
                        -- aegisub.log(0, "Warning: Inner parser stuck at Pos " .. current_pos_in_text_content .. " in Token '" .. text_content .. "'. Breaking token processing.\n")
                    end
                    break -- Exit the while loop for this text_content token
                end
            end -- End while current_pos_in_text_content
        end -- End if token.type
    end -- End for ipairs(tokens)

    for _, raw_segment in ipairs(current_line_raw_segments) do
        table.insert(result_text_parts, raw_segment)
    end
    if #result_text_parts > 0 and type(result_text_parts[#result_text_parts]) == "string" and result_text_parts[#result_text_parts]:match("%s+$") then
       result_text_parts[#result_text_parts] = result_text_parts[#result_text_parts]:match("^(.-)%s*$")
       if #result_text_parts[#result_text_parts] == 0 then table.remove(result_text_parts) end
    end

    local final_text_output_build = {}
    local previous_part_was_N = true 
    for _, part_val_from_result in ipairs(result_text_parts) do
        -- Stronger protection: Ensure part_val_str_safe is always a string
        local part_val_str_safe
        if type(part_val_from_result) == "string" then
            part_val_str_safe = part_val_from_result
        else
            part_val_str_safe = tostring(part_val_from_result)
            if type(part_val_str_safe) ~= "string" then -- If tostring itself returned nil (e.g. __tostring returned nil)
                part_val_str_safe = "" 
            end
        end

        if part_val_str_safe == "\\N" then
            if not previous_part_was_N then
                table.insert(final_text_output_build, part_val_str_safe)
                previous_part_was_N = true
            end
        -- The following line (or similar) was the error point if part_val_str_safe was nil.
        -- With the above assignment, part_val_str_safe is now guaranteed to be a string.
        elseif #part_val_str_safe > 0 then 
            local current_part_to_add = part_val_str_safe
            if previous_part_was_N then 
                current_part_to_add = current_part_to_add:match("^%s*(.*)")
                if type(current_part_to_add) ~= "string" then current_part_to_add = "" end 
            end
            if #current_part_to_add > 0 then -- # is safe as current_part_to_add is a string
                 table.insert(final_text_output_build, current_part_to_add)
                 previous_part_was_N = false
            elseif #current_part_to_add == 0 and #final_text_output_build > 0 and final_text_output_build[#final_text_output_build] == "\\N" then
                previous_part_was_N = true 
            end
        elseif #part_val_str_safe == 0 then 
            -- Explicitly ignore empty strings if they don't fall into the above logic
        end
    end

    if #final_text_output_build > 0 and final_text_output_build[#final_text_output_build] == "\\N" then
        table.remove(final_text_output_build)
    end
    
    local new_text_candidate = table.concat(final_text_output_build)
    if new_text_candidate ~= original_text then
        local clean_new_text, _ = get_visible_text_and_length(new_text_candidate)
        if type(clean_new_text) == "string" and #clean_new_text > 0 then
            line.text = new_text_candidate
        elseif total_visible_length > 0 and not (original_text:find("\\N", 1, true)) and #new_text_candidate == 0 then
            -- Prevent a non-empty line without \N from becoming empty
            line.text = original_text
            -- aegisub.log(0, "Note: Line break would have resulted in empty text for line: '" .. original_text .. "'. Original preserved.\n")
        elseif total_visible_length == 0 and not original_text:find("%S") then
             -- OK if original was already empty/whitespace
             line.text = new_text_candidate
        end
    end

    subs[line_index] = line
end

function apply_auto_line_breaks(subs, selected_ids)
    aegisub.progress.title(script_name .. " is running...") -- Translated string
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
