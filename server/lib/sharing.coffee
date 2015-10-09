plug = require './plug'
db = require('../helpers/db_connect_helper').db_connect()
async = require 'async'
request = require 'request-json'
request2 = require 'request'

# Contains all the sharing rules
# Avoid to request CouchDB for each document
rules = []

# Temporary : keep in memory the ids for the sharing
bufferIds = []


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

            console.log 'mapping results insert : ' + JSON.stringify mapResults
            matchAfterInsert mapResults, (err, acls) ->
                #acl :
                #console.log 'acls : ' + JSON.stringify acls

                return callback err if err?
                return callback null unless acls? and acls.length > 0


                startShares acls, (err) ->
                    callback err


# Map the upated document against all the sharing rules
module.exports.evalUpdate = (id, isBinaryUpdate, callback) ->
    # In some case, eg tasky, the doctype is not specified, whereas
    # it should be. Thus, the whole document is retrieved from db
    db.get id, (err, doc) ->
        console.log 'doc update : '  + JSON.stringify doc
        mapDocInRules doc, id, (err, mapResults) ->
            # mapResults: [ doc: {docID, userID, shareID, userParams, binaries},
            #              user: {docID, userID, shareID, userParams, binaries}]
            return callback err if err?

            console.log 'mapping results update : ' + JSON.stringify mapResults

            selectInPlug id, (err, selectResults) ->
                return callback err if err?

                updateProcess id, mapResults, selectResults, isBinaryUpdate, (err, res) ->
                    callback err, res

# Insert the map result as a tuple in PlugDB, as a Doc and/or as a User
# mapResult : {docID, userID, shareID, userParams}
insertResults = (mapResult, callback) ->

    console.log 'go insert docs'

    async.series [
        (_callback) ->
            # There is a doc result
            return _callback null unless mapResult?.doc?

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
            return _callback null unless mapResult?.user?

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
        #console.log 'tuples select : ' + JSON.stringify res if res?
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

        if mapRes?
            # do nothing, except in case of binaries
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

                        startShares [acls], (err) ->
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
                #console.log 'map and select not ok for ' + rule.id
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
            res = {}
            if isDoc then res.docID = id else res.userID = id
            res.shareID = shareID
            res.userParams = userParams
            res.binaries = binaries
            if isDoc then mapResult.doc = res else mapResult.user = res


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
                    binIds = getbinariesIds doc
                    saveResult id, rule.id, filterUser.userParam, binIds, false

                #console.log 'map result : ' + JSON.stringify mapResult
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
            ids = if doc.binaries? then doc.binaries else [doc.docID]

            plug.matchAll matchType, ids, doc.shareID, (err, acl) ->
                _callback err, acl
        ,
        (_callback) ->
            return _callback null unless mapResult.user?
            user = mapResult.user
            matchType = plug.DOCS
            ids = if user.binaries? then user.binaries else [user.userID]

            plug.matchAll matchType, ids, user.shareID, (err, acl) ->
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

    #console.log 'acls share : ' + JSON.stringify acls

    return callback null unless acls? and acls.length > 0

    async.each acls, (acl, _callback) ->
        async.parallel [
            (_cb) ->
                return _cb null unless acl.doc?
                sharingProcess acl.doc, (err) ->
                    _cb err
            ,
            (_cb) ->
                return _cb null unless acl.user?
                sharingProcess acl.user, (err) ->
                    _cb err
        ], (err) ->
            _callback err
    , (err) ->
        callback err

# Create the sharing for each user concerned
sharingProcess = (share, callback) ->
    #console.log 'share : ' + JSON.stringify share
    return callback null unless share? and share.users?

    async.each share.users, (user, _callback) ->

        # Get remote address based on userID
        getCozyAddressFromUserID user.userID, (err, url) ->
            # TODO : handle errors and empty url
            user.url = "http://192.168.50.6:9104" #TODO : change this

            # Start the full sharing process for one user
            userSharing share.shareID, user, share.docIDs, (err) ->
                _callback err

    , (err) ->
        callback err


# Cancel existing replication, create a new one, and save it
userSharing = (shareID, user, ids, callback) ->
    console.log 'share with user : ' + JSON.stringify user

    rule = getRuleById shareID
    return callback null unless rule?

    # Get the replicationID in rules based on the userID
    # Note : need to think more in case several users
    [replicationID, pwd] = getUserInfo rule.activeReplications, user.userID
    user.pwd = pwd
    console.log 'replication id : ' + replicationID + ' - pwd : ' + user.pwd
    # Replication exists for this user, cancel it
    if replicationID?
        cancelReplication replicationID, (err) ->
            return callback err if err?
            shareDocs user, ids, rule, (err) ->
                callback err


    # No active replication, notify the target
    else
        bufferIds = ids #TODO: remove this
        notifyTarget user, rule, (err) ->
            callback err



# Replicate documents and save the replication
shareDocs = (user, ids, rule, callback) ->

    replicateDocs user, ids, (err, repID) ->
        return callback err if err?

        saveReplication rule, user.userID, repID, user.pwd, (err) ->
            callback err, repID

notifyTarget = (user, rule,  callback) ->
    user.target = "http://192.168.50.6:9104"
    sharing =
        url: 'http://192.168.50.4:9104' #TODO: change this
        shareID: rule.id
        userID: user.userID
        desc: rule.name
    remote = request.newClient user.target
    remote.post "sharing/request", request: sharing, (err, res, body) ->
        console.log 'body : ' + JSON.stringify body
        error = err if err? and Object.keys(err).length > 0

        callback error

# Answer sent by the target
module.exports.targetAnswer = (req, res, next) ->
    console.log 'answer : ' + JSON.stringify req.body.answer
    answer = req.body.answer
    if answer.accepted is yes
        console.log 'target is ok for sharing, lets go'
        # find doc by share id and user by userid
        # update accepted: yes
        # replicate

        rule = getRuleById answer.shareID
        user =
            userID: answer.userID
            url: "http://192.168.50.6:9104"
            pwd: answer.password
        shareDocs user, bufferIds, rule, (err, repID) ->
            return next err if err?
            res.send 500 unless repID?
            res.send 200, repID
    else
        bufferIds = []
        console.log 'target is not ok for sharing, drop it'

module.exports.createNewShare = (req, res, next) ->
    console.log 'new share : ' + JSON.stringify req.body.share
    res.send 200

# Share the ids to the specifiedtarget
# TODO : do not replicate like a fool on the remote open couchdb port
# use the route https//cozy/dsApi/replication with credentials previously set
replicateDocs = (target, ids, callback) ->

    console.log 'lets replicate ' + JSON.stringify ids + ' on target ' + target.url
    console.log 'user : ' + target.userID + ' - pwd : ' + target.pwd

    return callback null unless target.url? and target.userID? and target.pwd?


    #couchClient = request.newClient "http://localhost:5984"
    sourceURL = "http://192.168.50.4:5984"
    #targetURL = target.url.replace "http://", "http://" + target.userID + ":" + target.pwd + "@"
    targetURL = target.url
    #targetURL = "http://pzjWbznBQPtfJ0es6cvHQKX0cGVqNfHW:NPjnFATLxdvzLxsFh9wzyqSYx4CjG30U@192.168.50.5:5984/cozy"
    couchClient = request.newClient sourceURL
    #couchTarget.setBasicAuth target.login, target.pwd

    repSourceToTarget =
        source: "cozy"
        target: targetURL + "/replication"
        #continuous: true
        doc_ids: ids


    # For bilateral sync; should be initiated by the target
    repTargetToSource =
        source: "cozy"
        target: sourceURL
        continuous: true
        doc_ids: ids

    console.log 'rep data : ' + JSON.stringify repSourceToTarget
    ###
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
            callback err, replicationID
            couchTarget.post "_replicate", repTargetToSource, (err, res, body)->
                if err? then callback err
                else if not body.ok
                    console.log JSON.stringify body
                    callback body
                else
                    console.log 'Replication from target suceeded \o/'
                    console.log JSON.stringify body
                    callback err, replicationID
            ###

    headers =
        'Content-Type': 'application/json'
    options =
        method: 'POST'
        headers: headers
        uri: sourceURL + "/_replicate"
    options['body'] = JSON.stringify repSourceToTarget
    request2 options, (err, res, body) ->
        console.log JSON.stringify body


# Update the sharing doc on the activeReplications field
updateActiveRep = (shareID, activeReplications, callback) ->

    db.get shareID, (err, doc) ->
        return callback err if err?
        # Overwrite the activeReplication field,
        # if it exists or not in the doc
        # Note that a merge would be more efficient in case of existence
        # but less easy to deal with
        doc.activeReplications = activeReplications
        console.log 'active rep : ' + JSON.stringify activeReplications
        db.save shareID, doc, (err, res) ->
            callback err

# Write the replication id in the sharing doc and save in RAM
saveReplication = (rule, userID, replicationID, pwd, callback) ->
    return callback null unless rule? and replicationID?


    console.log 'save replication ' + replicationID + ' with userid ' + userID
    console.log 'pwd : ' + pwd

    if rule.activeReplications?.length > 0
        isUpdate = false
        async.each rule.activeReplications, (rep, _callback) ->
            # Update repID if userID already exists
            if rep?.userID == userID
                rep.replicationID = replicationID
                isUpdate = true

            _callback null

        , (err) ->
            console.log 'is update : ' + isUpdate
            # insert a new replication if the userID didn't exist before
            if not isUpdate
                rule.activeReplications.push {userID, replicationID, pwd}

            updateActiveRep rule.id, rule.activeReplications, (err) ->
                callback err
    else
        rule.activeReplications = [{userID, replicationID, pwd}]
        updateActiveRep rule.id, rule.activeReplications, (err) ->
            callback err


# TODO : remove this : Deprecated
# Remove the replication from RAM and DB
removeReplication = (rule, replicationID, userID, callback) ->
    # Cancel the replication for couchDB
    return callback null unless rule? and replicationID?

    cancelReplication replicationID, (err) ->
        return callback err if err?

        # There are active replications
        if rule.activeReplications?
            async.each rule.activeReplications, (rep, _callback) ->
                if rep?.userID == userID
                    i = rule.activeReplications.indexOf rep
                    rule.activeReplications.splice i, 1 if i > -1
                    updateActiveRep rule.id, rule.activeReplications, (err) ->
                        _callback err
                else
                    _callback null
            , (err) ->
                callback err
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
        ids = (val.id for bin, val of doc.binary)
        #console.log 'binary ids : ' + JSON.stringify ids
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

                startShares [acls], (err) ->
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


# Utils - should be moved or removed
userInArray = (array, userID) ->
    if array?
        return yes for ar in array when ar.userID == userID
    return no

getUserInfo= (array, userID) ->
    if array?
        for activeRep in array
            if activeRep.userID == userID
                return [activeRep.replicationID, activeRep.pwd]
        return [null, null]
shareIDInArray = (array, shareID) ->
    if array?
        for ar in array
            return ar if ar?.doc? and ar.doc.shareID == shareID
            return ar if ar?.user? and ar.user.shareID == shareID
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
