java = require 'java'
jdbcJar = './plug/plug_api.jar'
java.classpath.push jdbcJar
plug = java.newInstanceSync 'org.cozy.plug.Plug'

#initialize PlugDB
init = (callback) ->
  # Setup the timeout handler
  timeoutProtect = setTimeout((->
    timeoutProtect = null
    callback error: 'PlugDB timed out'
    return
  ), 20000)
  plug.plugInit '/dev/ttyACM0', (err) ->
    if timeoutProtect
      clearTimeout timeoutProtect
      callback err
    return
  return

#insert docids and associated rules
insert = (ids, callback) ->
  #The js Object needs to be converted into a java String array
  array = java.newArray('java.lang.String', ids)
  plug.plugInsert array, (err) ->
    callback err
    return
  return

#select start on docs to return the ids
select = (callback) ->
  plug.plugSelect (err, result) ->
    callback err, result
    return
  return

#close the connection and save the data on flash
close = (callback) ->
  plug.plugClose (err) ->
    callback err
    return
  return

#Authenticate by fingerprint 
authFP = (callback) ->
  plug.plugFPAuthentication (err, authID) ->
    callback err, authID
    return
  return

exports.init = init
exports.insert = insert
exports.select = select
exports.close = close
exports.authFP = authFP

