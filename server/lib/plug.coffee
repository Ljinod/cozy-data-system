java = require 'java'
async = require 'async'
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

# Build functions to convert tupes into objects

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

# Tuples returned by plugdb are in format : [ [userID, docID] ]
buildACL = (tuples, shareid, callback) ->

    console.log 'build acl for tuples : ' + JSON.stringify tuples
    console.log 'shareid : ' + shareid

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

# Create a queue object with concurrency 1
# This is mandatory to deal correctly with PlugDB
q = async.queue (Plug, callback) ->
    p = Plug.params
    #console.log 'params : ' + JSON.stringify p

    if p[0] is 0 then plug.plugInsertDocs p[1], p[2], p[3], (err, res) ->
        callback err, res
    else if p[0] is 1 then plug.plugInsertUsers p[1], p[2], p[3], (err, res) ->
        callback err, res
    else if p[0] is 2 then plug.plugInsertDoc p[1], p[2], p[3], (err) ->
        callback err
    else if p[0] is 3 then plug.plugInsertUser p[1], p[2], p[3], (err) ->
        callback err
    else if p[0] is 4 then plug.plugSelectDocsByDocID p[1], (err, tuples) ->
        callback err, tuples
    else if p[0] is 5 then plug.plugSelectUsersByUserID p[1], (err, tuples) ->
        callback err, tuples
    else if p[0] is 6 then plug.plugMatchAll p[1], p[2], p[3], (err, tuples) ->
        console.log 'macth ok'
        callback err, tuples
    else if p[0] is 7 then plug.plugDeleteMatch p[1], p[2], p[3], (err) ->
        callback err, tuples
    else if p[0] is 8 then plug.plugInit p[1], (err, status) ->
        callback err, status
    else if p[0] is 9 then plug.plugInsertShare p[1], p[2], (err) ->
        callback err
    else
        callback()
, 1


# PlugDB API

#initialize DB
init = (callback) ->
    # Setup the timeout handler
    ###timeoutProtect = setTimeout((->
        timeoutProtect = null
        callback error: 'PlugDB timed out'
    ), 30000)
###
    port = '/dev/ttyACM0'
    params = [8, port]
    q.push {params}, (err, status) ->
        console.log 'status : ' + status
        #if timeoutProtect
        #    clearTimeout timeoutProtect
        if not err?
            console.log 'PlugDB is ready'
            IS_INIT = true
            BOOT_STATUS = status
        callback err
###
    plug.plugInit '/dev/ttyACM0', (err, status) ->
        if timeoutProtect
            clearTimeout timeoutProtect
            if not err?
                console.log 'PlugDB is ready'
                IS_INIT = true
                BOOT_STATUS = status

            callback err
###

#insert docids
insertDocs = (docids, shareid, userParams, callback) ->
    #The js Object needs to be converted into a java String array
    array = java.newArray('java.lang.String', docids)
    userParams = java.newArray('java.lang.String', userParams) if userParams?
    params = [0, array, shareid, userParams]
    q.push {params}, (err, res) ->
        console.log res + ' docs inserted'
        callback err

    #plug.plugInsertDocs array, shareid, userParams, (err) ->
    #    callback err

#insert userids
insertUsers = (userids, shareid, userParams, callback) ->
    #The js Object needs to be converted into a java String array
    array = java.newArray('java.lang.String', userids)
    userParams = java.newArray('java.lang.String', userParams) if userParams?
    params = [1, array, shareid, userParams]
    q.push {params}, (err, res) ->
        callback err
    #plug.plugInsertUsers array, shareid, userParams, (err) ->
    #    callback err

 #insert docid
insertDoc = (docid, shareid, userParams, callback) ->
    userParams = java.newArray('java.lang.String', userParams) if userParams?
    params = [2, docid, shareid, userParams]
    q.push {params}, (err) ->
        callback err

insertUser = (userid, shareid, userParams, callback) ->
    userParams = java.newArray('java.lang.String', userParams) if userParams?
    params = [3, userid, shareid, userParams]
    q.push {params}, (err) ->
        callback err

    #plug.plugInsertUser userid, shareid, userParams, (err) ->
    #    callback err

#insert sharing rule
insertShare = (shareid, description, callback) ->
    params = [9, shareid, description]
    q.push {params}, (err) ->
        callback err

#delete doc
deleteDoc = (idGlobal, callback) ->
    plug.plugDeleteDoc parseInt(idGlobal), (err) ->
        callback err

#delete user
deleteUser = (idGlobal, callback) ->
    plug.plugDeleteUser parseInt(idGlobal), (err) ->
        callback err

#delete share
deleteShare = (idGlobal, callback) ->
    plug.plugDeleteShare parseInt(idGlobal), (err) ->
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

# Select star on acl where docID = ?
# Returns an acl[][] array
selectDocsByDocID = (docid, callback) ->
    params = [4, docid]
    q.push {params}, (err, tuples) ->
        return callback err if err?

        buildSelect DOCS, tuples, (result) ->
            console.log 'select docs ok'
            callback null, result

    ###plug.plugSelectDocsByDocID docid, (err, tuples) ->
        if err? then callback err
        else
            buildSelect DOCS, tuples, (result) ->
                callback null, result
    ###

# Select star on users where userID = ?
# Returns an acl[][] array
selectUsersByUserID = (userid, callback) ->
    params = [5, userid]
    q.push {params}, (err, tuples) ->
        return callback err if err?

        buildSelect USERS, tuples, (result) ->
            callback null, result

    ###plug.plugSelectUsersByUserID userid, (err, tuples) ->
        if err? then callback err
        else
            buildSelect USERS, tuples, (result) ->
                callback null, result
    ###

# Match the doc/user to create new ACLs
# Returns an acl[][] array, containing all the [userids, docids] for
# the shareid
matchAll = (matchingType, ids, shareid, callback) ->
    array = java.newArray('java.lang.String', ids)
    params = [6, matchingType, array, shareid]
    q.push {params}, (err, tuples) ->
        console.log 'err match : ' + JSON.stringify err if err?

        return callback err if err?

        buildACL tuples, shareid, (acl) ->
            return callback err, acl
    ###
    plug.plugMatchAll matchingType, id, shareid, (err, tuples) ->
        buildACL tuples, shareid, (acl) ->
            callback err, acl
    ###

# Match the doc/user to create new ACLs
# Returns an acl[][] array, containing the inserted [userids, docids]
match = (matchingType, id, shareid, callback) ->
    plug.plugMatch matchingType, id, shareid, (err, result) ->
        callback err, result

# Delete the acl matching for a particular user or doc in a share
# Returns an acl[][] array, containing all the [userids, docids] for
# the shareid
deleteMatch = (matchingType, idPlug, shareid, callback) ->
    params = [7, matchingType, idPlug, shareid]
    q.push {params}, (err, tuples) ->
        return callback err if err?

        buildACL tuples, shareid, (acl) ->
            callback err, acl
    ###
    idPlug = parseInt(idPlug) # Necessary for java
    plug.plugDeleteMatch matchingType, idPlug, shareid, (err, tuples) ->
        buildACL tuples, shareid, (acl) ->
            callback err, acl
    ###


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
exports.insertUsers = insertUsers
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
