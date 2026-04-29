local config = {
  figure_dir = "figures_copy",
  figure_caption_section = "figure-caption-section",
  copy_figures = true,
  keep_figures = true,
  clean_figure_dir = true,
  figure_kinds = nil,
  source_data_dir = nil,
  copy_source_data = false,
}

local categories = {
  fig = {
    prefix = "Figure",
    space_before_numbering = true,
  },
}

local categories_by_name = {
  Figure = "fig",
}

local counters = {}
local figures = pandoc.List({})
local cleaned_figure_dirs = {}
local copy_file

local function meta_string(value)
  if value == nil then
    return nil
  end
  local result = pandoc.utils.stringify(value)
  if result == "" then
    return nil
  end
  return result
end

local function meta_bool(value, default)
  if value == nil then
    return default
  end
  if type(value) == "boolean" then
    return value
  end
  local text = string.lower(pandoc.utils.stringify(value))
  if text == "true" or text == "yes" or text == "1" then
    return true
  end
  if text == "false" or text == "no" or text == "0" then
    return false
  end
  return default
end

local function meta_string_list(value)
  if value == nil then
    return nil
  end
  if type(value) == "table" and value[1] ~= nil then
    local result = {}
    for _, item in ipairs(value) do
      local text = meta_string(item)
      if text ~= nil then
        result[text] = true
      end
    end
    return result
  end

  local text = meta_string(value)
  if text == nil then
    return nil
  end
  local result = {}
  for item in text:gmatch("[^,%s]+") do
    result[item] = true
  end
  return result
end

local function read_config(meta)
  local fc = meta["figure-collect"] or {}

  config.figure_dir =
    meta_string(fc["figure-dir"]) or
    meta_string(fc["output-dir"]) or
    config.figure_dir

  config.figure_caption_section =
    meta_string(fc["figure-caption-section"]) or
    config.figure_caption_section

  config.copy_figures = meta_bool(fc["copy-figures"], config.copy_figures)
  config.keep_figures = meta_bool(fc["keep-figures"], config.keep_figures)
  config.clean_figure_dir = meta_bool(fc["clean-figure-dir"], config.clean_figure_dir)
  config.figure_kinds = meta_string_list(fc["figure-kinds"]) or config.figure_kinds
  config.source_data_dir = meta_string(fc["source-data-dir"]) or config.source_data_dir
  config.copy_source_data = meta_bool(fc["copy-source-data"], config.copy_source_data)

  local crossref = meta.crossref or {}
  categories.fig.prefix =
    meta_string(crossref["fig-prefix"]) or
    meta_string(crossref["figure-prefix"]) or
    categories.fig.prefix

  local custom = crossref.custom
  if type(custom) == "table" then
    for _, item in ipairs(custom) do
      if meta_string(item.kind) == "float" then
        local key = meta_string(item.key)
        if key ~= nil then
          categories[key] = {
            prefix = meta_string(item["reference-prefix"]) or
              meta_string(item["caption-prefix"]) or
              key,
            space_before_numbering =
              meta_bool(item["space-before-numbering"], true),
          }
          categories_by_name[categories[key].prefix] = key
        end
      end
    end
  end
end

local function should_collect_kind(kind)
  return config.figure_kinds == nil or config.figure_kinds[kind] == true
end

local function suffix_for_kind(kind)
  if kind == "fig" then
    return ""
  end
  return "-" .. kind
end

local function figure_dir_for_kind(kind)
  return config.figure_dir .. suffix_for_kind(kind)
end

local function caption_section_for_kind(kind)
  return config.figure_caption_section .. suffix_for_kind(kind)
end

local function has_class(el, class)
  if el.classes == nil then
    return false
  end
  for _, value in ipairs(el.classes) do
    if value == class then
      return true
    end
  end
  return false
end

local function ref_kind(identifier)
  if identifier == nil or identifier == "" then
    return nil
  end
  if categories[identifier] ~= nil then
    return identifier
  end
  for key, _ in pairs(categories) do
    if identifier:match("^" .. key .. "%-") then
      return key
    end
  end
  return nil
end

local function next_label(kind)
  counters[kind] = (counters[kind] or 0) + 1
  local category = categories[kind] or categories.fig
  if category.space_before_numbering then
    return category.prefix .. " " .. tostring(counters[kind])
  end
  return category.prefix .. tostring(counters[kind])
end

local function first_image(blocks)
  local found = nil
  local node = blocks
  if pandoc.utils.type(blocks) == "Blocks" then
    node = pandoc.Div(blocks)
  end
  pandoc.walk_block(node, {
    Image = function(img)
      if found == nil then
        found = img
      end
      return img
    end,
  })
  return found
end

local function blocks_from_node(node)
  local node_type = pandoc.utils.type(node)
  if node == nil then
    return pandoc.Blocks({})
  elseif node_type == "Blocks" then
    return node
  elseif node_type == "Block" then
    return pandoc.Blocks({ node })
  elseif node_type == "Inlines" then
    return pandoc.Blocks({ pandoc.Plain(node) })
  elseif node.t == "Image" then
    return pandoc.Blocks({ pandoc.Plain({ node }) })
  end
  return pandoc.Blocks({})
end

local function block_has_image(block)
  local found = false
  pandoc.walk_block(block, {
    Image = function(img)
      found = true
      return img
    end,
  })
  return found
end

local function figure_caption_blocks(div)
  local caption = pandoc.Blocks({})
  for _, block in ipairs(div.content) do
    if not block_has_image(block) then
      caption:insert(block)
    end
  end
  return caption
end

local function caption_text(blocks)
  return pandoc.utils.stringify(pandoc.Div(blocks))
end

local function extension_for(path)
  local _, ext = pandoc.path.split_extension(path)
  if ext == nil or ext == "" then
    return ""
  end
  return ext
end

local function stem_for_path(path)
  local filename = pandoc.path.filename(path)
  local stem, _ = pandoc.path.split_extension(filename)
  return stem
end

local function safe_filename(label, ext)
  local name = label:gsub("[/\\:*?\"<>|]", "-")
  name = name:gsub("%s+", " ")
  return name .. ext
end

local function clean_figure_dir_once(dir)
  if config.clean_figure_dir and not cleaned_figure_dirs[dir] then
    if dir ~= nil and dir ~= "" and dir ~= "." and dir ~= "/" then
      pandoc.system.make_directory(dir, true)
      for _, file in ipairs(pandoc.system.list_directory(dir)) do
        os.remove(pandoc.path.join({ dir, file }))
      end
    end
    cleaned_figure_dirs[dir] = true
  end
end

local function copy_matching_source_data(src, label, kind)
  if not config.copy_source_data or config.source_data_dir == nil then
    return
  end

  local figure_stem = stem_for_path(src)
  local data_dir = config.source_data_dir
  local target_dir = figure_dir_for_kind(kind)

  pandoc.system.make_directory(data_dir, true)
  clean_figure_dir_once(target_dir)

  for _, file in ipairs(pandoc.system.list_directory(data_dir)) do
    local source_path = pandoc.path.join({ data_dir, file })
    local source_stem, source_ext = pandoc.path.split_extension(file)
    if source_stem == figure_stem or source_stem:match("^" .. figure_stem:gsub("([^%w])", "%%%1") .. "_") then
      local suffix = source_stem:sub(#figure_stem + 1)
      local renamed = safe_filename(label .. suffix, source_ext)
      copy_file(source_path, pandoc.path.join({ target_dir, renamed }))
    end
  end
end

copy_file = function(src, dest)
  clean_figure_dir_once(pandoc.path.directory(dest))

  pandoc.system.make_directory(pandoc.path.directory(dest), true)

  local input = io.open(src, "rb")
  if input == nil then
    io.stderr:write("[figure-collect] Could not read figure file: " .. src .. "\n")
    return
  end

  local contents = input:read("*all")
  input:close()

  local output = io.open(dest, "wb")
  if output == nil then
    io.stderr:write("[figure-collect] Could not write figure file: " .. dest .. "\n")
    return
  end

  output:write(contents)
  output:close()
end

local function prefixed_caption(label, blocks)
  local result = pandoc.Blocks({})
  local prefix = { pandoc.Str(label .. ":"), pandoc.Space() }
  local prefixed = false

  for _, block in ipairs(blocks) do
    if not prefixed and (block.t == "Para" or block.t == "Plain") then
      local content = pandoc.Inlines(prefix)
      content:extend(block.content)
      if block.t == "Para" then
        result:insert(pandoc.Para(content))
      else
        result:insert(pandoc.Plain(content))
      end
      prefixed = true
    else
      result:insert(block)
    end
  end

  if not prefixed then
    result:insert(pandoc.Para(prefix))
  end

  return result
end

local function collect_figure(div)
  local kind = ref_kind(div.identifier)
  if kind == nil then
    return nil
  end
  if not should_collect_kind(kind) then
    return div
  end

  local image = first_image(div.content)
  if image == nil then
    return nil
  end

  local caption = figure_caption_blocks(div)
  local label = next_label(kind)
  local src = image.src
  local dest = pandoc.path.join({
    figure_dir_for_kind(kind),
    safe_filename(label, extension_for(src)),
  })

  if config.copy_figures then
    copy_file(src, dest)
  end
  copy_matching_source_data(src, label, kind)

  figures:insert({
    id = div.identifier,
    kind = kind,
    label = label,
    src = src,
    dest = dest,
    caption = caption,
  })

  if config.keep_figures then
    return div
  end
  return {}
end

local function float_kind(float)
  local kind = ref_kind(float.identifier)
  if kind ~= nil then
    return kind
  end
  if float.type ~= nil then
    return categories_by_name[float.type]
  end
  return nil
end

local function collect_float(float)
  local kind = float_kind(float)
  if kind == nil then
    return nil
  end
  if not should_collect_kind(kind) then
    return float, false
  end

  local image = first_image(blocks_from_node(float.content))
  if image == nil then
    return float, false
  end

  local caption = blocks_from_node(float.caption_long)
  local label = next_label(kind)
  local src = image.src
  local dest = pandoc.path.join({
    figure_dir_for_kind(kind),
    safe_filename(label, extension_for(src)),
  })

  if config.copy_figures then
    copy_file(src, dest)
  end
  copy_matching_source_data(src, label, kind)

  figures:insert({
    id = float.identifier,
    kind = kind,
    label = label,
    src = src,
    dest = dest,
    caption = caption,
  })

  if config.keep_figures then
    return float, false
  end
  return {}, false
end

local function figure_caption_section(kind)
  local blocks = pandoc.Blocks({})
  for _, figure in ipairs(figures) do
    if figure.kind == kind then
      blocks:extend(prefixed_caption(figure.label, figure.caption))
    end
  end
  return blocks
end

local function replace_sections(doc)
  doc.blocks = doc.blocks:walk({
    Div = function(div)
      for kind, _ in pairs(categories) do
        if has_class(div, caption_section_for_kind(kind)) then
          div.content = figure_caption_section(kind)
          return div
        end
      end

      return div
    end,
  })

  return doc
end

return {
  {
    Meta = function(meta)
      read_config(meta)
      return meta
    end,
  },
  {
    Div = collect_figure,
    FloatRefTarget = collect_float,
  },
  {
    Pandoc = replace_sections,
  },
}
