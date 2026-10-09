local M = {}

-- Format only the inspection copy. Scan quoted attributes rather than splitting
-- on angle brackets, which can also occur inside attribute values and CDATA.
local function tokens(xml)
  local result, position = {}, 1
  while position <= #xml do
    if xml:sub(position, position) ~= "<" then
      local finish = xml:find("<", position, true) or (#xml + 1)
      table.insert(result, xml:sub(position, finish - 1))
      position = finish
    else
      local terminator
      if xml:sub(position, position + 3) == "<!--" then
        terminator = "-->"
      elseif xml:sub(position, position + 8) == "<![CDATA[" then
        terminator = "]]>"
      elseif xml:sub(position, position + 1) == "<?" then
        terminator = "?>"
      end
      local finish
      if terminator then
        local start = xml:find(terminator, position, true)
        if start then
          finish = start + #terminator - 1
        end
      else
        local quote
        for index = position + 1, #xml do
          local char = xml:sub(index, index)
          if quote then
            if char == quote then
              quote = nil
            end
          elseif char == '"' or char == "'" then
            quote = char
          elseif char == ">" then
            finish = index
            break
          end
        end
      end
      if not finish then
        return nil
      end
      table.insert(result, xml:sub(position, finish))
      position = finish + 1
    end
  end
  return result
end

local function tag_lines(tag, indent)
  local name, attributes, ending = tag:match("^(<[%w_:.-]+)%s+(.-)(/?>)$")
  if not name then
    return { indent .. tag }
  end
  local lines = { indent .. name }
  local position = 1
  while position <= #attributes do
    local start, finish = attributes:find("^%s*[%w_:.-]+%s*=%s*", position)
    if not start then
      return { indent .. tag }
    end
    local quote = attributes:sub(finish + 1, finish + 1)
    if quote ~= '"' and quote ~= "'" then
      return { indent .. tag }
    end
    local last = attributes:find(quote, finish + 2, true)
    if not last then
      return { indent .. tag }
    end
    table.insert(lines, indent .. "  " .. attributes:sub(start, last):gsub("^%s+", ""))
    position = last + 1
    if attributes:sub(position):match("^%s*$") then
      break
    end
  end
  lines[#lines] = lines[#lines] .. ending
  return lines
end

function M.lines(xml)
  local parts = tokens(xml)
  if not parts then
    return vim.split(xml, "\n", { plain = true })
  end
  local lines, depth = {}, 0
  for _, part in ipairs(parts) do
    local closing = part:match("^</")
    local opening = part:match("^<[%w_:.-]")
    if closing then
      depth = math.max(0, depth - 1)
    end
    if not part:match("^%s*$") then
      local indent = string.rep("  ", depth)
      local formatted = opening and tag_lines(part, indent) or { indent .. part }
      for _, line in ipairs(formatted) do
        vim.list_extend(lines, vim.split(line, "\n", { plain = true }))
      end
    end
    if opening and not part:match("/%s*>$") then
      depth = depth + 1
    end
  end
  return lines
end

return M
