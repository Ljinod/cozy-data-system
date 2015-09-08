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
    console.log 'doc insert : '  + JSON.stringify doc

    mapDocInRules doc, id, (err, mapResults) ->
        # mapResults : [ doc: {docID, userID, shareID, userParams, binaries},
        #                user: {docID, userID, shareID, userParams, binaries}]
        return callback err if err?

        # Serial loop, to avoid parallel db access
        async.eachSeries mapResults, insertResults, (err) ->
            return callback err if err?

            console.log 'mapping results : ' + JSON.stringify mapResults
            matchAfterInsert mapResults, (err, acls) ->
                #acl :
                console.log 'acls : ' + JSON.stringify acls

                return callback err if err?
                return callback null unless acls? and acls.length > 0


                startShares acls, (err) ->
                    callback err


# Map the upated document against all the sharing rules
module.exports.evalUpdate = (doc, id, isBinaryUpdate, callback) ->
    # Warning : in some case, eg tasky, the doctype is not specified, whereas
    # it should be. See more cases to decide how to handle it
    console.log 'doc update : '  + JSON.stringify doc
    mapDocInRules doc, id, (err, mapResults) ->
        # mapResults : [ {docID, userID, shareID, userParams} ]
        return callback err if err?

        selectInPlug id, (err, selectResults) ->
            return callback err if err?

            updateProcess id, mapResults, selectResults, isBinaryUpdate, (err, res) ->
                callback err, res

# Insert the map result as a tuple in PlugDB, as a Doc and/or as a User
# mapResult : {docID, userID, shareID, userParams}
insertResults = (mapResult, callback) ->

    console.log 'insert docs'

    async.series [
        (_callback) ->
            # There is a doc result
            return _callback null unless mapResult.doc?

            doc = mapResult.doc
            # The docid has already been inserted if there are binaries
            ids = if doc.binaries? then doc.binaries else [doc.docID]

            plug.insertDocs ids, doc.shareID, doc.userDesc, (err) ->
                unless err? then console.log "docs " + JSON.stringify ids +
                                        " inserted in PlugDB"
                if err? then _callback err else _callback null
        ,
        (_callback) ->
            # There is an user result
            return _callback null unless mapResult.user?

            user = mapResult.user
            # The userid has already been inserted if there are binaries
            ids = if user.binaries? then user.binaries else [user.userID]

            plug.insertUsers ids, user.shareID, user.userDesc, (err) ->
                unless err? then console.log "users " + JSON.stringify ids +
                                        " inserted in PlugDB"
                if err? then _callback err else _callback null

    ],
    (err) ->
        callback err




# Insert the map result as a tuple in PlugDB, as a Doc and/or as a User
# mapResult : {docID, userID, shareID, userParams}
updateResults = (mapResult, callback) ->
    async.series [
        (_callback) ->
            # There is a doc result
            if mapResult.docID?
                plug.insertDoc mapResult.docID, mapResult.shareID, \
                                mapResult.userDesc, (err) ->
                    unless err? then console.log "doc " + mapResult.docID +
                                            " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
        ,
        (_callback) ->
            # There is an user result
            if mapResult.userID?
                plug.insertUser mapResult.userID, mapResult.shareID, \
                                    mapResult.userDesc, (err) ->
                    unless err? then console.log "user " + mapResult.userID +
                                            " inserted in PlugDB"
                    if err? then _callback err else _callback null
            else
                _callback null
    ],
    (err) ->
        callback err

# Delete the matched ACL and the selected doc
deleteResults = (select, callback) ->
    async.series [
        (_callback) ->
            return _callback null unless select.doc?
            # There is a doc result
            doc = select.doc
            plug.deleteMatch plug.USERS, doc.idPlug, doc.shareID, (err, res) ->
                return _callback err if err?
                return _callback null unless res?

                plug.deleteDoc doc.idPlug, (err) ->
                    _callback err, res
        ,
        (_callback) ->
            return _callback null unless select.user?
            # There is a user result
            user = select.user
            plug.deleteMatch plug.DOCS, user.idPlug, \
                                user.shareID, (err, res) ->
                return _callback err if err?
                return _callback null unless res?

                plug.deleteDoc user.idPlug, (err) ->
                    _callback err, res

    ],
    (err, results) ->
        console.log 'delete results : ' + JSON.stringify results if results?
        acls = {doc: results[0], user: results[1]}
        callback err, acls

# Select doc by its id in PlugDB
selectInPlug = (id, callback) ->

    async.series [
        (_callback) ->
            plug.selectDocsByDocID id, (err, res) ->
                return _callback err if err?
                _callback null, res
        ,
        (_callback) ->
            plug.selectUsersByUserID id, (err, res) ->
                return _callback err if err?
                _callback null, res
    ],
    # results : [ [{selecDoc}], [{selectUser}] ]
    (err, results) ->
        res = {doc: results[0], user: results[1]}
        console.log 'tuples select : ' + JSON.stringify res if res?
        callback err, res


updateProcess = (id, mapResults, selectResults, isBinaryUpdate, callback) ->

    existDocOrUser = (shareID) ->
        if selectResults.doc?.shareID?
            doc = selectResults.doc if selectResults.doc.shareID == shareID
        if selectResults.user?.shareID?
            user =  selectResults.user if selectResults.user.shareID == shareID
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

                # Particular case for binaries
                if isBinaryUpdate
                    binaryHandling mapRes, (err) ->
                        _callback err
                else
                    _callback null

            # insert + match
            else
                console.log 'map ok for ' + rule.id

                insertResults mapRes, (err) ->
                    return _callback err if err?

                    matching mapRes, (err, acls) ->
                        return _callback err if err?
                        return _callback null unless acls?

                        sharingProcess acls, (err) ->
                            _callback err
        else
            # remove id in plug + invert match
            if selectResult.doc? || selectResult.user?
                console.log 'select ok for ' + rule.id
                deleteResults selectResult, (err, acls) ->
                    return _callback err if err?
                    return _callback null unless acls?

                    startShares acls, (err) ->
                        _callback err

            # do nothing
            else
                console.log 'map and select not ok for ' + rule.id
                _callback null
        _callback()

    async.eachSeries rules, evalUpdate, (err) ->
        callback err


# For each rule, evaluates if the document is correctly filtered/mapped
# as a document and/or a user
mapDocInRules = (doc, id, callback) ->

    # Evaluate a rule for the doc
    evalRule = (rule, _callback) ->

        mapResult = {}

        # Save the result of the mapping
        saveResult = (id, shareID, userParams, binaries, isDoc) ->
            doc = {}
            if isDoc then doc.docID = id else doc.userID = id
            doc.shareID = shareID
            doc.userParams = userParams
            doc.binaries = binaries
            if isDoc then mapResult.doc = doc else mapResult.user = doc


        filterDoc = rule.filterDoc
        filterUser = rule.filterUser

        # Evaluate the doc filter
        mapDoc doc, id, rule.id, filterDoc, (isDocMaped) ->
            if isDocMaped
                console.log 'doc maped !! '
                binIds = getbinariesIds doc
                saveResult id, rule.id, filterDoc.userParam, binIds, true

            # Evaluate the user filter
            mapDoc doc, id, rule.id, filterUser, (isUserMaped) ->
                if isUserMaped
                    console.log 'user maped !! '
                    saveResult id, rule.id, filterUser.userParam, binIds, false

                if not mapResult.doc? && not mapResult.user?
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
        async.mapSeries mapResults, matching, (err, acls) ->
            callback err, acls
    else
        callback null


# Send the match command to PlugDB
matching = (mapResult, callback) ->

    async.series [
        (_callback) ->
            return _callback null unless mapResult.doc?
            doc = mapResult.doc
            matchType = plug.USERS
            plug.matchAll matchType, doc.docID, doc.shareID, (err, acl) ->
                _callback err, acl
        ,
        (_callback) ->
            return _callback null unless mapResult.user?
            user = mapResult.user
            matchType = plug.DOCS
            plug.matchAll matchType, user.userID, user.shareID, (err, acl) ->
                _callback err, acl
    ],
    (err, results) ->
        acls = {doc: results[0], user: results[1]}
        callback err, acls

    #if acl?
    # Add the shareID at the beginning
    # acl = Array.prototype.slice.call( acl )
    # acl.unshift mapResult.shareID




startShares = (acls, callback) ->
    # acls.user are the acl for the user matching
    # acls.doc are the acl for the doc matching

    console.log 'acls share : ' + JSON.stringify acls

    return callback null unless acls? and acls.length > 0

    async.each acls, (acl, _callback) ->
        async.parallel [
            (_cb) ->
                return _cb null unless acl.doc?
                sharingProcess acl.doc, (err) ->
                    console.log 'cb parallel doc'
                    _cb err
            ,
            (_cb) ->
                return _callback null unless acl.user?
                sharingProcess acl.user, (err) ->
                    console.log 'cb parallel user'
                    _cb err
        ], (err) ->
            _callback err
    , (err) ->
        callback err


sharingProcess = (share, callback) ->
    console.log 'share : ' + JSON.stringify share
    return callback null unless share? and share.users?

    async.each share.users, (user, _callback) ->

        # Get remote address based on userID
        getCozyAddressFromUserID user.userID, (err, url) ->
            # TODO : handle errors and empty url
            user.target = url

            # Start the full sharing process for one user
            userSharing share.shareID, user, share.docIDs, (err) ->
                if err? then _callback err else _callback null

    , (err) ->
        console.log 'callback sharing process'
        callback err






# Cancel existing replication, create a new one, and save it
userSharing = (shareID, user, ids, callback) ->
    console.log 'share with user : ' + JSON.stringify user

    rule = getRuleById shareID
    return callback null unless rule?

    # Get the replicationID in rules based on the userID
    # Note : need to think more in case several users
    replicationID = getRepID rule.activeReplications, user.userID
    console.log 'replication id : ' + replicationID
    # Replication exists for this user, cancel it
    if replicationID?
        removeReplication rule, replicationID, (err) ->
            return callback err unless err?

            shareDocs user, ids, rule, (err) ->
                callback err
    # No active replication
    else
        shareDocs user, ids, rule, (err) ->
            callback err


# Replication documents and save the replication
shareDocs = (user, ids, rule, callback) ->

    replicateDocs user.target, ids, (err, repID) ->
        return callback err if err?

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
        return err unless callback err?
        # Overwrite the activeReplication field,
        # if it exists or not in the doc
        # Note that a merge would be more efficient in case of existence
        # but less easy to deal with
        doc.activeReplications = activeReplications
        db.save shareID, doc, (err, res) ->
            callback err

# Write the replication id in the sharing doc and save in RAM
saveReplication = (rule, userID, replicationID, callback) ->

    console.log 'save replication ' + replicationID

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
    return callback null unless rule? and replicationID?

    cancelReplication replicationID, (err) ->
        return callback err if err?
        # There are active replications
        if rule.activeReplications?
            for rep, i in rule.activeReplications
                if rep.replicationID == replicationID
                    rule.activeReplications.splice i, 1
                    updateActiveRep rule.id, rule.activeReplications, (err) ->
                        return callback err if err?
                callback null
        # There is normally no replication written in DB, but check it
        # anyway to avoid ghost data
        else
            updateActiveRep rule.id, [], (err) ->
                callback err



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
            # If !body.ok, the replication failed,
            # but we consider it's not an error
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

getbinariesIds= (doc) ->
    if doc.binary?
        ids = (bin.id for bin in doc.binary)
        console.logs 'binary ids : ' + console.log JSON.stringify ids
        return ids

binaryHandling = (mapRes, callback) ->
    # TODO : handle this case :
    # The doc already had binaries : check previous ones in plugdb
    # and update it : retrieve previous ids in binary.coffee
    # beware to handle sequentials select properly

    if mapRes.doc.binaries? or mapRes.user.binaries?
        console.log 'go insert binaries'

        insertResults mapRes, (err) ->
            return callback err if err?

            matching mapRes, (err, acls) ->
                return callback err if err?
                return callback null unless acls?

                sharingProcess acls, (err) ->
                    callback err


    # This is not normal and probably an error in the execution order
    else
        console.log 'no binary in the doc'
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

# PlugDB access
#Select doc into PlugDB
module.exports.selectDocPlug = (id, callback) ->
    plug.selectSingleDoc id, (err, tuple) ->
        callback err, tuple

#Select user into PlugDB
module.exports.selectUserPlug = (id, callback) ->
    plug.selectSingleUser id, (err, tuple) ->
        callback err, tuple

# Save the sharing rule in RAM and PlugDB
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
        for ar in array
            return ar if ar.doc? and ar.doc.shareID == shareID
            return ar if ar.user? and ar.user.shareID == shareID
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
