plug = require './plug'
db = require('../helpers/db_connect_helper').db_connect()
async = require 'async'
request = require 'request-json'

# Contains all the sharing rules
# Avoid to request CouchDB for each document
rules = []


# Map the inserted document against all the sharing rules
# If one or several mapping are trigerred, the result {id, shareID, userParams}
# will be inserted in PlugDB as a Doc and/or a User
module.exports.evalInsert = (doc, id, callback) ->
    mapDocInRules doc, id, (err, mapResults) ->
        # mapResults : [ {docID, userID, shareID, userParams} ]
        if err? then callback err
        else
            # Serial loop, to avoid parallel db access
            async.eachSeries mapResults, insertResults, (err) ->
                if err?
                    callback err
                else
                    console.log 'mapping results : ' + JSON.stringify mapResults
                    matchAfterInsert mapResults, (err, acls) ->
                        if err? then callback err
                        else if acls? && acls.length > 0
                            startShares acls, (err) ->
                                callback err
                        else
                            callback null

# Map the upated document against all the sharing rules
module.exports.evalUpdate = (doc, id, callback) ->
    # Warning : in some case, eg tasky, the doctype is not specified, whereas
    # it should be. See more cases to decide how to handle it
    console.log 'doc update : '  + JSON.stringify doc
    mapDocInRules doc, id, (err, mapResults) ->
        # mapResults : [ {docID, userID, shareID, userParams} ]
        if err?
            callback err
        else
            selectInPlug id, (err, selectResults) ->
                if err? then callback err
                else
                    console.log 'select results : ' + JSON.stringify selectResults
                    updateProcess id, mapResults, selectResults, (err, res) ->
                        callback err, res

        # Serial loop, to avoid parallel db access
        ###async.eachSeries mapResults, updateResults, (err) ->
            console.log 'mapping results : ' + JSON.stringify mapResults
            callback err, mapResults
            ###

# Insert the map result as a tuple in PlugDB, as a Doc and/or as a User
# mapResult : {docID, userID, shareID, userParams}
insertResults = (mapResult, callback) ->

    async.series [
        (_callback) ->
            # There is a doc result
            if mapResult.docID?
                plug.insertDoc mapResult.docID, mapResult.shareID, mapResult.userDesc, (err) ->
                    unless err? then console.log "doc " + mapResult.docID +
                                            " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
        ,
        (_callback) ->
            # There is an user result
            if mapResult.userID?
                plug.insertUser mapResult.userID, mapResult.shareID, mapResult.userDesc, (err) ->
                    unless err? then console.log "user " + mapResult.userID +
                                            " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
    ],
    (err) ->
        callback err

deleteResults = (select, callback) ->
    async.series [
        (_callback) ->
            # There is a doc result
            if select.doc?
                plug.deleteMatch plug.USERS, select.doc.idPlug, select.doc.shareID, (err, res) ->
                    if err? then _callback err
                    else
                        if res? and res.length > 0
                            plug.deleteDoc select.doc.idPlug, (err) ->
                                _callback err, res
                        else
                            _callback null
            else
                _callback null
        ,
        (_callback) ->
            # There is a user result
            if select.user?
                plug.deleteMatch plug.DOCS, select.user.idPlug, select.user.shareID, (err, res) ->
                    if err? then _callback err
                    else
                        if res? and res.length > 0
                            plug.deleteDoc select.user.idPlug, (err) ->
                                _callback err, res
                        else
                            _callback null
            else
                _callback null
    ],
    (err, results) ->
        console.log 'delete results : ' + JSON.stringify results if results?
        callback err, results


# Insert the map result as a tuple in PlugDB, as a Doc and/or as a User
# mapResult : {docID, userID, shareID, userParams}
updateResults = (mapResult, callback) ->
    async.series [
        (_callback) ->
            # There is a doc result
            if mapResult.docID?
                plug.insertDoc mapResult.docID, mapResult.shareID, mapResult.userDesc, (err) ->
                    unless err? then console.log "doc " + mapResult.docID +
                                            " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
        ,
        (_callback) ->
            # There is an user result
            if mapResult.userID?
                plug.insertUser mapResult.userID, mapResult.shareID, mapResult.userDesc, (err) ->
                    unless err? then console.log "user " + mapResult.userID +
                                            " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
    ],
    (err) ->
        callback err


selectInPlug = (id, callback) ->

    async.series [
        (_callback) ->
            plug.selectDocsByDocID id, (err, res) ->
                if err? then _callback err
                else
                    #res = convertTuples tuples
                    _callback null, res
        ,
        (_callback) ->
            plug.selectUsersByUserID id, (err, res) ->
                if err? then _callback err
                else
                    #res = convertTuples tuples
                    _callback null, res
    ],
    # results : [ [{selecDoc}], [{selectUser}] ]
    (err, results) ->
        console.log 'tuples select : ' + JSON.stringify results if results
        callback err, results


updateProcess = (id, mapResults, selectResults, callback) ->

    existDocOrUser = (shareID) ->
        if selectResults[0]? and selectResults[0].shareID?
            doc = selectResults[0] if selectResults[0].shareID == shareID
            console.log 'doc : ' + JSON.stringify doc
        if selectResults[1]? and selectResults[1].shareID?
            user =  selectResults[1] if selectResults[1].shareID == shareID
        return {doc, user}

    evalUpdate = (rule, _callback) ->
        # There is probably a way to optimize here :
        # For each sharing rule, loop on map and select results...
        mapRes = shareIDInArray mapResults, rule.id
        selectResult = existDocOrUser rule.id
        console.log 'map res : ' + JSON.stringify mapRes
        console.log 'select result : ' + JSON.stringify selectResult

        if mapRes?
            # do nothing
            if selectResult.doc? || selectResult.user?
                console.log 'map and select ok for ' + rule.id
                _callback null
            # insert + match
            else
                console.log 'map ok for ' + rule.id

                # TODO : must be done in series to avoid multiple inserts/select
                # TODO : create matchin function to simplify
                insertResults mapRes, (err) ->
                    if err? then _callback err
                    else
                        matching mapRes, (err, acl) ->
                            if err then _callback err
                            else
                                if acl?
                                    sharingProcess acl, (err) ->
                                        _callback err
                                else
                                    _callback null
        else
            # remove id in plug + invert match
            if selectResult.doc? || selectResult.user?
                console.log 'select ok for ' + rule.id
                deleteResults selectResult, (err, acls) ->
                    if err? then _callback err
                    else if acls?
                        startShares acls, (err) ->
                            _callback err
                    else
                        _callback null

            # do nothing
            else
                console.log 'map and select not ok for ' + rule.id
                _callback null
        _callback()

    async.eachSeries rules, evalUpdate, (err) ->
        callback err

#Select doc into PlugDB
module.exports.selectDocPlug = (id, callback) ->
    plug.selectSingleDoc id, (err, tuple) ->
        callback err, tuple

#Select user into PlugDB
module.exports.selectUserPlug = (id, callback) ->
    plug.selectSingleUser id, (err, tuple) ->
        callback err, tuple

# For each rule, evaluates if the document is correctly filtered/mapped
# as a document and/or a user
mapDocInRules = (doc, id, callback) ->

    # Evaluate a rule for the doc
    evalRule = (rule, _callback) ->

        mapResult =
            docID: null
            userID: null
            shareID: null
            userParams: null

        # Save the result of the mapping
        saveResult = (id, shareID, userParams, isDoc) ->
            if isDoc then mapResult.docID = id else mapResult.userID = id
            mapResult.shareID = shareID
            mapResult.userParams = userParams

        filterDoc = rule.filterDoc
        filterUser = rule.filterUser

        # Evaluate the doc filter
        mapDoc doc, id, rule.id, filterDoc, (docMaped) ->
            if docMaped then console.log 'doc maped !! '
            saveResult id, rule.id, filterDoc.userParam, true if docMaped

            # Evaluate the user filter
            mapDoc doc, id, rule.id, filterUser, (userMaped) ->
                if userMaped then console.log 'user maped !! '
                saveResult id, rule.id, filterUser.userParam, false if userMaped

                if not mapResult.docID? && not mapResult.userID?
                    _callback null, null
                else
                    _callback null, mapResult

    # Evaluate all the rules
    # mapResults : [ {docID, userID, shareID, userParams} ]
    async.map rules, evalRule, (err, mapResults) ->
        # Convert to array and remove null results
        mapResults = Array.prototype.slice.call( mapResults )
        removeNullValues mapResults
        callback err, mapResults


# Generic map : evaluate the rule in the filter against the doc
mapDoc = (doc, docID, shareID, filter, callback) ->
    if eval filter.rule
        if filter.userDesc then ret = eval filer.userDesc else ret = true
        callback ret
    else
        callback false



# Call the matching operator in PlugDB and share the results if any
matchAfterInsert = (mapResults, callback) ->

    # Match all results
    if mapResults? and mapResults.length > 0
        # Convert to array
        console.log 'mapResults : ' + JSON.stringify mapResults
        async.mapSeries mapResults, matching, (err, acls) ->
            callback err, acls
    else
        callback null


# Send the match command to PlugDB
matching = (mapResult, callback) ->
    console.log 'go match : ' + JSON.stringify mapResult

    if mapResult.docID?
        matchType = plug.USERS
        id = mapResult.docID
    else if mapResult.userID?
        matchType = plug.DOCS
        id = mapResult.userID
    else
        callback null

    #if acl?
    # Add the shareID at the beginning
    # acl = Array.prototype.slice.call( acl )
    # acl.unshift mapResult.shareID
    plug.matchAll matchType, id, mapResult.shareID, (err, acl) ->
        callback err, acl

startShares = (acls, callback) ->
    async.each acls, sharingProcess, (err) ->
        callback err


sharingProcess = (share, callback) ->
    console.log 'share : ' + JSON.stringify share
    if share? and share.users?
        async.each share.users, (user, _callback) ->

            # Get remote address based on userID
            getCozyAddressFromUserID user.userID, (err, url) ->
                # TODO : handle errors and empty url
                user.target = url

                # Start the full sharing process for one user
                userSharing share.shareID, user, share.docIDs, (err) ->
                    if err? then _callback err else _callback null

        , (err) ->
            callback err
    else
        callback null

# Cancel existing replication, create a new one, and save it
userSharing = (shareID, user, ids, callback) ->
    console.log 'share with user : ' + JSON.stringify user

    rule = getRuleById shareID
    if rule?
        # Get the replicationID in rules based on the userID
        # Note : need to think more in case several users
        replicationID = getRepID rule.activeReplications, user.userID
        console.log 'replication id : ' + replicationID
        # Replication exists for this user, cancel it
        if replicationID?
            removeReplication rule, replicationID, (err) ->
                if err? then callback err
                else
                    shareDocs user, ids, rule, (err) ->
                        callback err
        # No active replication
        else
            shareDocs user, ids, rule, (err) ->
                callback err
    else
        callback null

# Replication documents and save the replication
shareDocs = (user, ids, rule, callback) ->
    replicateDocs user.target, ids, (err, repID) ->
        if err? then callback err
        else
            saveReplication rule, user.userID, repID, (err) ->
                callback err


# Share the ids to the specifiedtarget
replicateDocs = (target, ids, callback) ->

    console.log 'lets replicate ' + JSON.stringify ids + ' on target ' + target

    couchClient = request.newClient "http://localhost:5984"
    sourceURL = "http://192.168.50.4:5984/cozy"
    targetURL = "http://pzjWbznBQPtfJ0es6cvHQKX0cGVqNfHW:NPjnFATLxdvzLxsFh9wzyqSYx4CjG30U@192.168.50.5:5984/cozy"
    couchTarget = request.newClient targetURL

    repSourceToTarget =
        source: "cozy"
        target: targetURL
        continuous: true
        doc_ids: ids

    # For bilateral sync; should be initiated by the target
    repTargetToSource =
        source: "cozy"
        target: sourceURL
        continuous: true
        doc_ids: ids

    couchClient.post "_replicate", repSourceToTarget, (err, res, body) ->
        #err is sometimes empty, even if it has failed
        if err? then callback err
        else if not body.ok
            console.log JSON.stringify body
            callback body
        else
            console.log 'Replication from source suceeded \o/'
            console.log JSON.stringify body
            replicationID = body._local_id
            couchTarget.post "_replicate", repTargetToSource, (err, res, body)->
                if err? then callback err
                else if not body.ok
                    console.log JSON.stringify body
                    callback body
                else
                    console.log 'Replication from target suceeded \o/'
                    console.log JSON.stringify body
                    callback err, replicationID



# Update the sharing doc on the activeReplications field
updateActiveRep = (shareID, activeReplications, callback) ->

    db.get shareID, (err, doc) ->
        if err? then callback err
        else
            # Overwrite the activeReplication field, if it exists or not in the doc
            # Note that a merge would be more efficient in case of existence
            # but less easy to deal with
            doc.activeReplications = activeReplications
            db.save shareID, doc, (err, res) ->
                callback err

# Write the replication id in the sharing doc and save in RAM
saveReplication = (rule, userID, replicationID, callback) ->

    if rule? and replicationID?
        if rule.activeReplications?
            rule.activeReplications.push {userID, replicationID}
            # Save the new replication id in the share document
            updateActiveRep rule.id, rule.activeReplications, (err) ->
                callback err
        else
            rule.activeReplications = [{userID, replicationID}]
            updateActiveRep rule.id, rule.activeReplications, (err) ->
                callback err
    else
        callback null

# Remove the replication from RAM and DB
removeReplication = (rule, replicationID, callback) ->
    # Cancel the replication for couchDB
    if rule? and replicationID?
        cancelReplication replicationID, (err) ->
            if err? then callback err
            else
                # There are active replications
                if rule.activeReplications?
                    for rep, i in rule.activeReplications
                        if rep.replicationID == replicationID
                            rule.activeReplications.splice i, 1
                            updateActiveRep rule.id, rule.activeReplications, (err) ->
                                callback err if err?
                    callback null
                # There is normally no replication written in DB, but check it anyway
                # to avoid ghost data
                else
                    updateActiveRep rule.id, [], (err) ->
                        callback err
    else
        callback null

# Interrupt the running replication
cancelReplication = (replicationID, callback) ->
    couchClient = request.newClient "http://localhost:5984"
    args =
        replication_id: replicationID
        cancel: true
    console.log 'cancel args ' + JSON.stringify args

    couchClient.post "_replicate", args, (err, res, body) ->
        if err? then callback err
        else
            console.log 'Cancel replication'
            # If !body.ok, the replication failed, but we consider it's not an error
            console.log JSON.stringify body
            callback()

# Get the url of a contact to share data  with him.
# If there is no url defined, nothing will be share, but
# eventually a modal should appear to ask the owner to manually
# enter the url
getCozyAddressFromUserID = (userID, callback) ->
    if userID?
        db.get userID, (err, user) ->
            console.log 'user url : ' + user.url if user?
            if err?
                callback err
            else
                callback null, user.url
    else
        callback null




# Get the current replications ids
getActiveTasks = (client, callback) ->
    client.get "_active_tasks", (err, res, body) ->
        if err? or not body.length?
            callback err
        else
            for task in body
                repIds = task.replication_id if task.replication_id
            callback null, repIds




# TODO : API to manage sharing rules
module.exports.createRule = (doc, callback) ->
module.exports.deleteRule = (doc, callback) ->
module.exports.updateRule = (doc, callback) ->

# Save the sharinf rule in RAM and PlugDB
saveRule = (rule, callback) ->
    id = rule._id
    name = rule.name
    filterDoc = rule.filterDoc
    filterUser = rule.filterUser
    activeReplications = rule.activeReplications if rule.activeReplications

    rules.push {id, name, filterDoc, filterUser, activeReplications}

module.exports.insertRules = (callback) ->
    insertShare = (rule, _callback) ->
        plug.insertShare rule.id, '', (err) ->
            _callback err
    async.eachSeries rules, insertShare, (err) ->
        console.log 'rules inserted' unless err?
        callback err

# Called at the DS initialization
# Note : for the moment a new rule implies a ds reboot to be evaluated
module.exports.initRules = (callback) ->
    db.view 'sharingRule/all', (err, rules) ->
        return callback new Error("Error in view") if err?
        rules.forEach (rule) ->
            saveRule rule

        callback()


# Utils - should be moved
userInArray = (array, userID) ->
    if array?
        return yes for ar in array when ar.userID == userID
    return no

getRepID= (array, userID) ->
    if array?
        for activeRep in array
            return activeRep.replicationID if activeRep.userID == userID

shareIDInArray = (array, shareID) ->
    if array?
        console.log 'array : ' + JSON.stringify array
        return ar for ar in array when ar.shareID == shareID
    return null

getRuleById = (shareID, callback) ->
    for rule in rules
        return rule if rule.id == shareID


removeNullValues = (array) ->
    if array?
        for i in [array.length-1..0]
            array.splice(i, 1) if array[i] is null

removeDuplicates = (array) ->
    if array.length == 0
        return []
    res = {}
    res[array[key]] = array[key] for key in [0..array.length-1]
    value for key, value of res

convertTuples = (tuples, callback) ->
    if tuples?
        array = []
        for tuple in tuples
            res =
                shareID: tuple[2]
                userParams: tuple[3]
            array.push res
        return array
