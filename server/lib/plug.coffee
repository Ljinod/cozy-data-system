java = require 'java'
jdbcJar = './plug/plug_api.jar'
java.classpath.push jdbcJar
plug = java.newInstanceSync 'org.cozy.plug.Plug'

IS_INIT = false
BOOT_STATUS = 0
USERS = 0
DOCS = 1

isInit = ->
    return IS_INIT

bootStatus = ->
    return BOOT_STATUS


buildSelect = (table, tuples, callback) ->
    if tuples?
        array = []
        for tuple in tuples
            res =
                idPlug: tuple[0]
                userID: tuple[1] if table is 0
                docID: tuple[1] if table is 1
                shareID: tuple[2]
                userParams: tuple[3]
            array.push res
        callback res
    else
        callback null

buildSelectDoc = (tuples, callback) ->
    if tuples?
        array = []
        for tuple in tuples
            res =
                idPlug: tuple[0]
                docID: tuple[1]
                shareID: tuple[2]
                userParams: tuple[3]
            array.push res
        callback res
    else
        callback null

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

#delete doc
deleteDoc = (idGlobal, callback) ->
    plug.plugDeleteDoc idGlobal, (err) ->
        callback err

#delete user
deleteUser = (idGlobal, callback) ->
    plug.plugDeleteUser idGlobal, (err) ->
        callback err

#delete share
deleteShare = (idGlobal, callback) ->
    plug.plugDeleteShare idGlobal, (err) ->
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
selectDocsByDocID = (docid, callback) ->
    plug.plugSelectDocsByDocID docid, (err, tuples) ->
        if err? then callback err
        else
            buildSelect DOCS, tuples, (result) ->
                callback null, result

# Select star on users where userID = ?
# Returns an acl[][] array
selectUsersByUserID = (userid, callback) ->
    plug.plugSelectUsersByUserID userid, (err, tuples) ->
        if err? then callback err
        else
            buildSelect USERS, tuples, (result) ->
                callback null, result

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

# Delete the acl matching for a particular user or doc in a share
# Returns an acl[][] array, containing all the [userids, docids] for
# the shareid
deleteMatch = match = (matchingType, idPlug, shareid, callback) ->
    console.log 'go delete ' + matchingType + ' on id ' + idPlug + ' share id: ' + shareid
    plug.plugDeleteMatch matchingType, idPlug, shareid, (err, tuples) ->
        buildACL tuples, shareid, (acl) ->
            callback err, acl



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

exports.USERS = USERS
exports.DOCS = DOCS

exports.isInit = isInit
exports.bootStatus = bootStatus

exports.init = init
exports.insertDocs = insertDocs
exports.insertDoc = insertDoc
exports.insertUser = insertUser
exports.insertShare = insertShare
exports.deleteDoc = deleteDoc
exports.deleteUser = deleteUser
exports.deleteShare = deleteShare
exports.selectDocs = selectDocs
exports.selectUsers = selectUsers
exports.selectDocsByDocID = selectDocsByDocID
exports.selectUsersByUserID = selectUsersByUserID
exports.matchAll = matchAll
exports.match = match
exports.deleteMatch = deleteMatch
exports.close = close
exports.authFP = authFP
