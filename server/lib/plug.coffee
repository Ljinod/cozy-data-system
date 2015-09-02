java = require 'java'
jdbcJar = './plug/plug_api.jar'
java.classpath.push jdbcJar
plug = java.newInstanceSync 'org.cozy.plug.Plug'

IS_INIT = false
BOOT_STATUS = 0

isInit = ->
    return IS_INIT

bootStatus = ->
    return BOOT_STATUS

#initialize PlugDB
init = (callback) ->
    # Setup the timeout handler
    timeoutProtect = setTimeout((->
        timeoutProtect = null
        callback error: 'PlugDB timed out'
    ), 30000)

    plug.plugInit '/dev/ttyACM0', (err, status) ->
        if timeoutProtect
            clearTimeout timeoutProtect
            if not err?
                console.log 'PlugDB is ready'
                IS_INIT = true
                BOOT_STATUS = status

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
 #insert docids and associated rules
insertUser = (userid, shareid, userParams, callback) ->
    plug.plugInsertUser userid, shareid, userParams, (err) ->
        callback err

#insert sharing rule
insertShare = (shareid, description, callback) ->
    plug.plugInsertShare shareid, description, (err) ->
        callback err

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

# Select star on docs where docID = ?
# Returns an acl[][] array
plugSelectDocsByDocID = (docid, callback) ->
    plug.plugSelectDocsByDocID docid, (err, result) ->
        callback err, result

# Select star on users where userID = ?
# Returns an acl[][] array
plugSelectUsersByUserID = (userid, callback) ->
    plug.plugSelectUsersByUserID userid, (err, result) ->
        callback err, result

# Match the doc/user to create new ACLs
# Returns an acl[][] array, containing all the [userids, docids] for
# the shareid
matchAll = (matchingType, id, shareid, callback) ->
    plug.plugMatchAll matchingType, id, shareid, (err, tuples) ->
        buildACL tuples, shareid, (acl) ->
            callback err, acl

# Match the doc/user to create new ACLs
# Returns an acl[][] array, containing the inserted [userids, docids]
match = (matchingType, id, shareid, callback) ->
    plug.plugMatch matchingType, id, shareid, (err, result) ->
        callback err, result

buildACL = (tuples, shareid, callback) ->

    userInArray = (array, userID) ->
        if array?
            return yes for ar in array when ar.userID == userID
        return no

    if tuples?
        res =
            shareID: shareid
            users: []
            docIDs: []

        for tuple in tuples
            res.users.push {userID: tuple[0]} unless userInArray res.users, tuple[0]
            res.docIDs.push tuple[1] unless res.users.length > 1

        callback res
    else
        callback null

#close the connection and save the data on flash
close = (callback) ->
    console.log 'go close'
    plug.plugClose (err) ->
        if err
            callback err
        else
            IS_INIT = false
            callback null

#Authenticate by fingerprint
authFP = (callback) ->
  plug.plugFPAuthentication (err, authID) ->
    callback err, authID
    return
  return

exports.MATCH_USERS = 0
exports.MATCH_DOCS = 1

exports.isInit = isInit
exports.bootStatus = bootStatus

exports.init = init
exports.insertDocs = insertDocs
exports.insertDoc = insertDoc
exports.insertUser = insertUser
exports.insertShare = insertShare
exports.selectDocs = selectDocs
exports.selectUsers = selectUsers
exports.plugSelectDocsByDocID = plugSelectDocsByDocID
exports.plugSelectUsersByUserID = plugSelectUsersByUserID
exports.matchAll = matchAll
exports.match = match
exports.close = close
exports.authFP = authFP
