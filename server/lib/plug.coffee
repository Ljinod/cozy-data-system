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
    ), 30000)

    plug.plugInit '/dev/ttyACM0', (err) ->
        if timeoutProtect
            clearTimeout timeoutProtect
            console.log 'PlugDB ready'
            callback err

#insert docids and associated rules
insertDocs = (ids, callback) ->
  #The js Object needs to be converted into a java String array
  array = java.newArray('java.lang.String', ids)
  plug.plugInsertDocs array, (err) ->
    callback err
    return
  return

 #insert docids and associated rules
insertDoc = (docid, shareid, userParams, callback) ->
  plug.plugInsertDoc docid, shareid, userParams, (err) ->
    callback err
    return
  return

 #insert docids and associated rules
insertUser = (userid, shareid, userParams, callback) ->
  plug.plugInsertDoc docid, shareid, userParams, (err) ->
    callback err
    return
  return

#select docs to return the ids
selectDocs = (callback) ->
  plug.plugSelectDocs (err, results) ->
    callback err, results
    return
  return

 #select docs to return the ids
selectUsers = (callback) ->
  plug.plugSelectUsers (err, results) ->
    callback err, results
    return
  return

#select star on docs to return the ids
selectSingleDoc = (docid, callback) ->
  plug.plugSelectSingleDoc docid, (err, result) ->
    callback err, result
    return
  return

#select star on docs to return the ids
selectSingleUser = (userid, callback) ->
  plug.plugSelectSingleUser userid, (err, result) ->
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
exports.insertDocs = insertDocs
exports.insertDoc = insertDoc
exports.insertUser = insertUser
exports.selectDocs = selectDocs
exports.selectUsers = selectUsers
exports.selectSingleDoc = selectSingleDoc
exports.selectSingleUser = selectSingleUser
exports.close = close
exports.authFP = authFP
