plug = require './plug'
db = require('../helpers/db_connect_helper').db_connect()
async = require 'async'

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
        for i in [mapResults.length-1..0]
            mapResults.splice(i, 1) if mapResults[i] is null

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
    if mapResults?
        async.mapSeries mapResults, matching, (err, acls) ->
            console.log 'acls : ' + JSON.stringify acls if acls

            callback err, acls
    else
        callback null

matching = (mapResult, callback) ->
    async.series [
        (_callback) ->
            if mapResult.docid?
                plug.matchAll plug.MATCH_USERS, mapResult.docid, mapResult.shareid, (err, acls) ->
                    console.log 'res match : ' + JSON.stringify acls if acls?
                    _callback err, acls
            else
                _callback null
        ,
        (_callback) ->
            if mapResult.userid?
                plug.matchAll plug.MATCH_DOCS, mapResult.userid, mapResult.shareid, (err, acls) ->
                    #share if result
                    console.log 'res match : ' + JSON.stringify acls if acls?
                    _callback err, acls
            else
                _callback null
    ],
    (err, matchResults) ->
        console.log 'match results : ' + JSON.stringify matchResults if matchResults?
        callback err, matchResults

# Share the ids to the specifiedtarget
shareDocs = (target, ids) ->
    couchClient = request.newClient "http://localhost:5984"
    sourceURL = "http://localhost:5984/cozy"
    targetURL = "http://pzjWbznBQPtfJ0es6cvHQKX0cGVqNfHW:NPjnFATLxdvzLxsFh9wzyqSYx4CjG30U@192.168.50.5:5984/cozy"

    repSourceToTarget =
        source: "cozy"
        target: targetURL
        continuous: true
        doc_ids: ids

    # For bilateral sync; should be initiated by the target
    repTargetToSource =
        source: "cozy"
        target: source
        continuous: true
        doc_ids: ids

    couchClient.post "_replicate", repSourceToTarget, (err, res, body) ->
        #err is sometimes empty, even if it has failed
        if err or not body.ok
            console.log JSON.stringify body
            console.log "Replication from source failed"
            callback err

        else
            console.log 'Replication from source suceeded \o/'
            console.log JSON.stringify body
            replicationID = body._local_id
            couchTarget.post "_replicate", repTargetToSource, (err, res, body) ->
                if err or not body.ok
                    console.log JSON.stringify body
                    console.log "Replication from target failed"
                    callback err

                else
                    console.log 'Replication from target suceeded \o/'
                    console.log JSON.stringify body
                    callback err, replicationID

# Write the replication id in the sharing doc and save in RAM
saveReplication = (rule, replicationID, callback) ->
    if rule? and replicationID?
        # See cradle : https://github.com/flatiron/cradle
        if rule.activeReplications
            rule.activeReplications.push replicationID
        else
            rule.activeReplications = [replicationID]

        console.log 'active replications : ' + JSON.stringify rule.activeReplications
        # Save the new replication id in the share document
        db.save ruleID, {activeReplications: rule.activeReplications}, (err, res) ->
            console.log JSON.stringify res
            callback err, res

    callback null



# Get the url of a contact to share data  with him.
# If there is no url defined, nothing will be share, but
# eventually a modal should appear to ask the owner to manually
# enter the url
getCozyAddressFromUserID = (userID, callback) ->



# Interrupt the running replication
cancelReplication = (client, replicationID, callback) ->
    client.post "_replicate", {replication_id: replicationID, cancel:true}, (err, res, body) ->
        if err or not body.ok
            console.log "Cancel replication failed"
            callback err
        else
            console.log 'Cancel replication ok'
            callback()

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
        console.log 'sharing rules inserted in plug db' if not err
        callback err

# Called on the DS initialization
# Note : for the moment a new rule implies a ds reboot to be evaluated
module.exports.initRules = (callback) ->
    db.view 'sharingRules/all', (err, rules) ->
        return callback new Error("Error in view") if err?
        rules.forEach (rule) ->
            saveRule rule

        callback()
