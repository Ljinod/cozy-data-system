plug = require './plug'
db = require('../helpers/db_connect_helper').db_connect()
async = require 'async'
request = require 'request-json'

# Contains all the sharing rules
# Avoid to request CouchDB for each document
rules = []

# Map the inserted document against all the sharing rules
# If one or several mapping are trigerred, the result {id, shareid, userParams}
# will be inserted in PlugDB as a Doc and/or a User
module.exports.mapDocOnInsert = (doc, id, callback) ->
    mapDocInRules doc, id, (err, mapResults) ->
        # mapResults : [ {docid, userid, shareid, userParams} ]
        if err
            callback err
        else
            # Serial loop, to avoid parallel db access
            async.eachSeries mapResults, insertResults, (err) ->
                console.log 'results : ' + JSON.stringify mapResults
                callback err, mapResults

# Insert the map result as a tuple in PlugDB, as a Doc and/or as a User
# mapResult : {docid, userid, shareid, userParams}
insertResults = (mapResult, callback) ->

    async.series [
        (_callback) ->
            # There is a doc result
            if mapResult.docid?
                plug.insertDoc mapResult.docid, mapResult.shareid, mapResult.userDesc, (err) ->
                    if not err? then console.log "doc " + mapResult.docid + " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
        ,
        (_callback) ->
            # There is an user result
            if mapResult.userid?
                plug.insertUser mapResult.userid, mapResult.shareid, mapResult.userDesc, (err) ->
                    if not err? then console.log "user " + mapResult.userid + " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
    ],
    (err) ->
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
            docid: null
            userid: null
            shareid: null
            userParams: null

        # Save the result of the mapping
        saveResult = (id, shareid, userParams, isDoc) ->
            if isDoc then mapResult.docid = id else mapResult.userid = id
            mapResult.shareid = shareid
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

                if not mapResult.docid? && not mapResult.userid?
                    _callback null, null
                else
                    _callback null, mapResult

    # Evaluate all the rules
    # mapResults : [ {docid, userid, shareid, userParams} ]
    async.map rules, evalRule, (err, mapResults) ->
        # Convert to array and remove null results
        mapResults = Array.prototype.slice.call( mapResults )
        removeNullValues mapResults
        callback err, mapResults


# Generic map : evaluate the rule in the filter against the doc
mapDoc = (doc, docid, shareid, filter, callback) ->
    #console.log 'eval ' + JSON.stringify filter.rule + ' for the doc ' + JSON.stringify doc
    if eval filter.rule
        if filter.userDesc then ret = eval filer.userDesc else ret = true
        callback ret
    else
        callback false

# Call the matching operator in PlugDB and share the results if any
module.exports.matchAfterInsert = (mapResults, callback) ->

    # Send the match command to PlugDB
    matching = (mapResult, _callback) ->
        if mapResult.docid?
            matchType = plug.MATCH_USERS
            id = mapResult.docid
        else
            matchType = plug.MATCH_DOCS
            id = mapResult.userid

        plug.matchAll matchType, id, mapResult.shareid, (err, acl) ->
            if acl?
                acl = Array.prototype.slice.call( acl )
                acl.unshift mapResult.shareid
            #(acl.push mapResult.shareid for acl in acls when acl is not null) if acls?
            #console.log 'res match : ' + JSON.stringify acl if acl?

            _callback err, acl

    # Match all results
    if mapResults?
        async.mapSeries mapResults, matching, (err, acls) ->
            if err
                callback err
            else
                removeNullValues acls

                if acls? && acls.length > 0
                    startShares acls, (err) ->
                        callback err
                else
                    callback null
    else
        callback null

startShares = (acls, callback) ->

    buildShare = (acl, _callback) ->
        share =
            shareID: null
            users: []
            docIDs: []

        # Each acl concerns one sharing rule
        for id,i in acl
            if i == 0
                share.shareID = id
            else
                userID = id[0]
                docID = id[1]
                share.users.push {userID} unless userInArray share.users, userID
                share.docIDs.push docID unless share.users.length > 1
        _callback null, share

    async.map acls, buildShare, (err, shares) ->
        console.log 'shares : ' + JSON.stringify shares
        for share in shares
            for user in share.users
                # Get remote address based on userid
                getCozyAddressFromUserID user.userID, (err, url) ->
                    # TODO : handle errors and empty url
                    user.target = url
                    shareDocs
                    # Replicate ids to targets url
                    replicateDocs user.target, share.docIDs, (err, replicationID) ->
                        if err?
                            callback err
                        else
                            # bind shareid to acl?
                            saveReplication share.shareID, replicationID, (err, res) ->
                                callback err, res


shareDocs = (shareID, user, ids, callback) ->
    rule = getRuleById share.shareID
    if rule? and rule.activeReplications?
        # Replication exists for this user, cancel it
        replicationID = getRepID rule.activeReplications, user.userID
        if replicationID?
            cancelReplication replicationID, (err) ->
                if err?
                    callback err
                else
                    replicateDocs user.target, ids, (err, repID) ->
                        saveReplication shareID, repID, (err, res)
                            callback err, res
        else
            replicateDocs user.target, ids, (err, repID) ->
                saveReplication shareID, repID, (err, res)
                    callback err, res




# Share the ids to the specifiedtarget
replicateDocs = (target, ids, callback) ->

    console.log 'lets replicate ' + ids + ' on target ' + target

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
        if err
            callback err
        else if not body.ok
            console.log JSON.stringify body
            callback body
        else
            console.log 'Replication from source suceeded \o/'
            console.log JSON.stringify body
            replicationID = body._local_id
            couchTarget.post "_replicate", repTargetToSource, (err, res, body) ->
                if err
                    callback err
                else if not body.ok
                    console.log JSON.stringify body
                    callback body
                else
                    console.log 'Replication from target suceeded \o/'
                    console.log JSON.stringify body
                    callback err, replicationID

# Write the replication id in the sharing doc and save in RAM
saveReplication = (shareID, replicationID, callback) ->

    if shareID? and replicationID?
        # Get the rule by its id
        rule = getRuleById shareID
        console.log 'rule id found : ' + rule.id + ' for shareid ' + shareID

        #console.log 'rule found : ' + JSON.stringify rule
        if rule?
            if rule.activeReplications?
                rule.activeReplications.push replicationID
                # Save the new replication id in the share document
                db.merge rule.id, {activeReplications: rule.activeReplications}, (err, res) ->
                    console.log 'res merge : ' + JSON.stringify res
                    callback err, res
            else
                rule.activeReplications = [replicationID]
                db.get shareID, (err, doc) ->
                    doc.activeReplications = rule.activeReplications
                    db.save shareID, doc, (err, res) ->
                        console.log 'res save : ' + JSON.stringify res
                        callback err, res

        else
            console.log 'no rule found with share id ' + shareID
    else
        console.log 'no shareid given'

    callback null

# Interrupt the running replication
cancelReplication = (replicationID, callback) ->
    couchClient = request.newClient "http://localhost:5984"
    couchClient.post "_replicate", {replication_id: replicationID, cancel:true}, (err, res, body) ->
        if err
            callback err
        else if not body.ok
            console.log JSON.stringify body
            callback body
        else
            console.log 'Cancel replication ok'
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
        if err or not body.length?
            callback err
        else
            repIds = (task.replication_id for task in body when task.replication_id)
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
        callback err

# Called at the DS initialization
# Note : for the moment a new rule implies a ds reboot to be evaluated
module.exports.initRules = (callback) ->
    db.view 'sharingRules/all', (err, rules) ->
        return callback new Error("Error in view") if err?
        rules.forEach (rule) ->
            saveRule rule

        callback()


# Utils - should be moved
userInArray = (array, userID) ->
    return yes for ar in array when ar.userID == userID
    return no

getRepID= (array, userID) ->
    return repID for activeRep in array when activeRep.userID == userID

getRuleById = (shareID, callback) ->
    for rule in rules
        return rule if rule.id == shareID


removeNullValues = (array) ->
    for i in [array.length-1..0]
        array.splice(i, 1) if array[i] is null

removeDuplicates = (array) ->
    if array.length == 0
        return []
    res = {}
    res[array[key]] = array[key] for key in [0..array.length-1]
    value for key, value of res
