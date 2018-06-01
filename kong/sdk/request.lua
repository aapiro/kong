local cjson = require "cjson.safe"
local multipart = require "multipart"


local ngx = ngx
local sub = string.sub
local find = string.find
local lower = string.lower
local type = type
local error = error
local tonumber = tonumber


local function new(self)
  local _REQUEST = {}


  local MIN_HEADERS            = 1
  local MAX_HEADERS_DEFAULT    = 100
  local MAX_HEADERS            = 1000
  local MIN_QUERY_ARGS         = 1
  local MAX_QUERY_ARGS_DEFAULT = 100
  local MAX_QUERY_ARGS         = 1000
  local MIN_POST_ARGS          = 1
  local MAX_POST_ARGS_DEFAULT  = 100
  local MAX_POST_ARGS          = 1000

  local MIN_PORT               = 1
  local MAX_PORT               = 65535

  local CONTENT_TYPE           = "Content-Type"

  local CONTENT_TYPE_POST      = "application/x-www-form-urlencoded"
  local CONTENT_TYPE_JSON      = "application/json"
  local CONTENT_TYPE_FORM_DATA = "multipart/form-data"

  local X_FORWARDED_PROTO      = "X-Forwarded-Proto"
  local X_FORWARDED_HOST       = "X-Forwarded-Host"
  local X_FORWARDED_PORT       = "X-Forwarded-Port"


  function _REQUEST.get_scheme()
    return ngx.var.scheme
  end


  function _REQUEST.get_host()
    return ngx.var.host
  end


  function _REQUEST.get_port()
    return tonumber(ngx.var.server_port)
  end


  function _REQUEST.get_forwarded_scheme()
    if self.ip.is_trusted(self.client.get_ip()) then
      local scheme = _REQUEST.get_header(X_FORWARDED_PROTO)
      if scheme then
        return lower(scheme)
      end
    end

    return _REQUEST.get_scheme()
  end


  function _REQUEST.get_forwarded_host()
    if self.ip.is_trusted(self.client.get_ip()) then
      local host = _REQUEST.get_header(X_FORWARDED_HOST)
      if host then
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        return s and lower(sub(host, 1, s - 1)) or lower(host)
      end
    end

    return _REQUEST.get_host()
  end


  function _REQUEST.get_forwarded_port()
    if self.ip.is_trusted(self.client.get_ip()) then
      local port = tonumber(_REQUEST.get_header(X_FORWARDED_PORT))
      if port and port >= MIN_PORT and port <= MAX_PORT then
        return port
      end

      local host = _REQUEST.get_header(X_FORWARDED_HOST)
      if host then
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        if s then
          port = tonumber(sub(host, s + 1))

          if port and port >= MIN_PORT and port <= MAX_PORT then
            return port
          end
        end
      end
    end

    return _REQUEST.get_port()
  end


  function _REQUEST.get_http_version()
    return ngx.req.http_version()
  end


  function _REQUEST.get_method()
    return ngx.req.get_method()
  end


  function _REQUEST.get_path()
    local uri = ngx.var.request_uri
    local s = find(uri, "?", 2, true)
    return s and sub(uri, 1, s - 1) or uri
  end


  function _REQUEST.get_raw_query()
    return ngx.var.args or ""
  end


  function _REQUEST.get_query_arg(name)
    if type(name) ~= "string" then
      error("query argument name must be a string", 2)
    end

    local arg_value = _REQUEST.get_query()[name]
    if type(arg_value) == "table" then
      return arg_value[1]
    end

    return arg_value
  end


  function _REQUEST.get_query(max_args)
    if max_args == nil then
      return ngx.req.get_uri_args(MAX_QUERY_ARGS_DEFAULT)
    end

    if type(max_args) ~= "number" then
      error("max_args must be a number", 2)
    end

    if max_args < MIN_QUERY_ARGS then
      error("max_args must be >= " .. MIN_QUERY_ARGS, 2)
    end

    if max_args > MAX_QUERY_ARGS then
      error("max_args must be <= " .. MAX_QUERY_ARGS, 2)
    end

    return ngx.req.get_uri_args(max_args)
  end


  function _REQUEST.get_header(name)
    if type(name) ~= "string" then
      error("header name must be a string", 2)
    end

    local header_value = _REQUEST.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  function _REQUEST.get_headers(max_headers)
    if max_headers == nil then
      return ngx.req.get_headers(MAX_HEADERS_DEFAULT)
    end

    if type(max_headers) ~= "number" then
      error("max_headers must be a number", 2)

    elseif max_headers < MIN_HEADERS then
      error("max_headers must be >= " .. MIN_HEADERS, 2)

    elseif max_headers > MAX_HEADERS then
      error("max_headers must be <= " .. MAX_HEADERS, 2)
    end

    return ngx.req.get_headers(max_headers)
  end


  function _REQUEST.get_raw_body()
    ngx.req.read_body()

    local body = ngx.req.get_body_data()
    if not body then
      if ngx.req.get_body_file() then
        return nil, "request body did not fit into client body buffer, consider raising 'client_body_buffer_size'"

      else
        return ""
      end
    end

    return body
  end


  function _REQUEST.get_body(mimetype, max_args)
    local content_type = mimetype or _REQUEST.get_header(CONTENT_TYPE)
    if not content_type then
      return nil, "missing content type"
    end

    local content_type_lower = lower(content_type)
    do
      local s = find(content_type_lower, ";", 1, true)
      if s then
        content_type_lower = sub(content_type_lower, 1, s - 1)
      end
    end

    if find(content_type_lower, CONTENT_TYPE_POST, 1, true) == 1 then
      if max_args ~= nil then
        if type(max_args) ~= "number" then
          error("max_args must be a number", 2)

        elseif max_args < MIN_POST_ARGS then
          error("max_args must be >= " .. MIN_POST_ARGS, 2)

        elseif max_args > MAX_POST_ARGS then
          error("max_args must be <= " .. MAX_POST_ARGS, 2)
        end
      end

      -- TODO: should we also compare content_length to client_body_buffer_size here?

      ngx.req.read_body()
      local pargs, err = ngx.req.get_post_args(max_args or MAX_POST_ARGS_DEFAULT)
      if not pargs then
        return nil, err, CONTENT_TYPE_POST
      end

      return pargs, nil, CONTENT_TYPE_POST

    elseif find(content_type_lower, CONTENT_TYPE_JSON, 1, true) == 1 then
      local body, err = _REQUEST.get_raw_body()
      if not body then
        return nil, err, CONTENT_TYPE_JSON
      end

      -- TODO: cjson.decode_array_with_array_mt(true) (?)
      local json = cjson.decode(body)
      if not json then
        return nil, "invalid json body", CONTENT_TYPE_JSON
      end

      return json, nil, CONTENT_TYPE_JSON

    elseif find(content_type_lower, CONTENT_TYPE_FORM_DATA, 1, true) == 1 then
      local body, err = _REQUEST.get_raw_body()
      if not body then
        return nil, err, CONTENT_TYPE_FORM_DATA
      end

      -- TODO: multipart library doesn't support multiple fields with same name
      return multipart(body, content_type):get_all(), nil, CONTENT_TYPE_FORM_DATA

    else
      return nil, "unsupported content type '" .. content_type .. "'", content_type_lower
    end
  end


  return _REQUEST
end


return {
  new = new,
}
