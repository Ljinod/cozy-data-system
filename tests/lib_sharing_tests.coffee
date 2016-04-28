should    = require('chai').Should()
helpers   = require('./helpers')
sinon     = require 'sinon'
_         = require 'lodash'
rewire    = require 'rewire'
httpMocks = require 'node-mocks-http'
request   = require 'request-json'

# connection to test db
db = require("#{helpers.prefix}server/helpers/db_connect_helper").db_connect()

# client used to connect
client = helpers.getClient()
client.setBasicAuth "home", "token"

# What we test
Sharing = rewire "#{helpers.prefix}server/lib/sharing"


describe 'Lib sharing: ', ->

    # clear test db
    before helpers.clearDB db
    # start test application
    before helpers.startApp
    # stop it when tests are done
    after helpers.stopApp



    describe 'getDomain module', ->

        # Since the `getDomain` module is not exported we need to rewire it
        getDomain  = Sharing.__get__ 'getDomain'
        dbViewStub = {}

        before (done) ->
            dbViewStub = sinon.stub db, "view", (path, callback) ->
                instance = [value: {domain: 'domain'}]
                callback null, instance
            done()

        after (done) ->
            dbViewStub.restore()
            done()


        it 'should return the domain when all information is available',
        (done) ->
            getDomain (err, domain) ->
                should.not.exist err
                domain.should.deep.equal "https://domain/"
                done()

        it 'should return an error when db.view fails', (done) ->
            dbViewStub.restore() # cancel default stub
            error = new Error "db.view"
            # replace it with one that throws an error
            dbViewStub = sinon.stub db, "view", (path, callback) ->
                callback error

            getDomain (err, domain) ->
                should.not.exist domain
                err.should.deep.equal error
                done()

        it 'should return null when information is missing', (done) ->
            dbViewStub.restore() # cancel previous stub
            dbViewStub = sinon.stub db, "view", (path, callback) ->
                instance = ['phony data']
                callback null, instance

            getDomain (err, domain) ->
                should.not.exist domain
                should.not.exist err
                done()


    describe 'checkDomain module', ->

        # `checkDomain` is not exported, rewire needed
        checkDomain = Sharing.__get__ 'checkDomain'

        it 'should return an error when `getDomain` returns an error', (done) ->
            error = new Error 'Sharing.getDomain'
            getDomainStub = (callback) ->
                callback error
            Sharing.__set__ 'getDomain', getDomainStub

            checkDomain null, (err, url) ->
                should.not.exist url
                err.should.deep.equal error
                done()

        it 'should return an error when `getDomain` returns nothing', (done) ->
            getDomainStub = (callback) ->
                callback null
            Sharing.__set__ 'getDomain', getDomainStub

            checkDomain null, (err, url) ->
                should.not.exist url
                err.should.deep.equal new Error 'No instance domain set'
                done()

        it 'should return the domain retrieved by `getDomain`', (done) ->
            domain = 'https://domain/'
            getDomainStub = (callback) ->
                callback null, domain
            Sharing.__set__ 'getDomain', getDomainStub

            checkDomain null, (err, url) ->
                should.not.exist err
                url.should.deep.equal domain
                done()

        it 'should return the url when it is already set', (done) ->
            predefined_url = "https://test.cozycloud.cc/"

            checkDomain predefined_url, (err, url) ->
                should.not.exist err
                url.should.deep.equal predefined_url
                done()


    describe 'handleNotifyResponse module', ->

        handleNotifyResponse = Sharing.__get__ 'handleNotifyResponse'

        it 'should return the error when it exists', (done) ->
            error = new Error "Sharing.handleNotifyResponse"
            handleNotifyResponse error, null, null, (err) ->
                err.should.deep.equal error
                done()

        it 'should return an error when result does not exist', (done) ->
            expected_error        = new Error "Bad request"
            expected_error.status = 400

            handleNotifyResponse null, null, {data: 'data'}, (err) ->
                err.should.deep.equal expected_error
                done()

        it 'should return an error when result.statusCode does not exist',
        (done) ->
            expected_error        = new Error "Bad request"
            expected_error.status = 400

            handleNotifyResponse null, {status: 'failure'}, {data: 'data'},
            (err) ->
                err.should.deep.equal expected_error
                done()

        it 'should return an error when body.error exists', (done) ->
            body = {error: 'Resource not found'}

            handleNotifyResponse null, {statusCode: 404}, body, (err) ->
                err.should.equal body
                err.error.should.deep.equal body.error
                err.status.should.equal 404
                done()

        it 'should return an error when result.statusCode does not equal 200',
        (done) ->
            expected_error        = new Error "The request has failed"
            expected_error.status = 302

            handleNotifyResponse null, {statusCode: 302}, {data: 'data'},
            (err) ->
                err.should.deep.equal expected_error
                done()

        it 'should call the callback when none of the above occurred', (done) ->
            handleNotifyResponse null, {statusCode: 200}, {data: 'data'},
            (err) ->
                should.not.exist err
                done()


    describe 'notifyRecipient module', ->

        # stub are declared here so that we can restore them
        requestCreateClientStub = {}
        checkDomainStub         = {}

        params =
            sharerUrl   : 'sharerUrl'
            recipientUrl: 'recipientUrl'

        before (done) ->
            requestCreateClientStub = sinon.stub request, 'createClient',
                (url) ->
                    # check that we request the correct url: that of the
                    # RECIPIENT
                    url.should.deep.equal params.recipientUrl
                    return post: (path, params, callback) ->
                        callback null, {statusCode: 200}, {data: 'data'}

            done()

        after (done) ->
            requestCreateClientStub.restore()
            done()

        it 'should return an error when `checkDomain` fails', (done) ->
            error = new Error "Sharing.checkDomain"
            checkDomainFn = (url, callback) ->
                callback error
            checkDomainStub = Sharing.__set__ 'checkDomain', checkDomainFn

            Sharing.notifyRecipient 'path', params , (err) ->
                err.should.deep.equal error
                done()

        it 'should send the notification to the recipient', (done) ->
            checkDomainStub() # cancel stub

            Sharing.notifyRecipient 'path', params, (err) ->
                    should.not.exist err
                    done()


    describe 'notifySharer module', ->

        # stub are declared here so that we can restore them
        requestCreateClientStub = {}
        checkDomainStub         = {}

        params =
            sharerUrl   : 'sharerUrl'
            recipientUrl: 'recipientUrl'

        before (done) ->
            requestCreateClientStub = sinon.stub request, 'createClient',
                (url) ->
                    # check that we request the correct url: that of the
                    # SHARER
                    url.should.deep.equal params.sharerUrl
                    return post: (path, params, callback) ->
                        callback null, {statusCode: 200}, {data: 'data'}

            done()

        after (done) ->
            requestCreateClientStub.restore()
            done()

        it 'should return an error when `checkDomain` fails', (done) ->
            error = new Error "Sharing.checkDomain"
            checkDomainFn = (url, callback) ->
                callback error
            checkDomainStub = Sharing.__set__ 'checkDomain', checkDomainFn

            Sharing.notifySharer 'path', params , (err) ->
                err.should.deep.equal error
                done()

        it 'should send the notification to the sharer', (done) ->
            checkDomainStub() # cancel stub

            Sharing.notifySharer 'path', params, (err) ->
                    should.not.exist err
                    done()


    describe 'replicateDocs module', ->

        # Correct params structure
        params =
            id        : 'shareID'
            target    :
                recipientUrl: 'https://recipientUrl'
                token       : 'token'
            docIDs    : ['docID_1', 'docID_2', 'docID_3']
            continuous: true
        # url with credentials
        cred              = "#{params.id}:#{params.target.token}"
        url_w_credentials = _.cloneDeep params.target.recipientUrl
        url_w_credentials = url_w_credentials.replace "://", "://#{cred}@"
        # target of replication: concatenation of the url with the credentials
        # and a route especially defined (and hardcoded)
        replication_target = url_w_credentials +
            "/services/sharing/replication/"

        # this error is going to be tested against in the first tests so we
        # declare it once and for all here
        error        = new Error 'Parameters missing'
        error.status = 400

        # stub and hooks
        dbReplicateStub = {}

        before (done) ->
            dbReplicateStub = sinon.stub db, 'replicate',
                (url, replication, callback) ->
                    replication.source.should.deep.equal "cozy" # hardcoded
                    replication.target.should.deep.equal replication_target
                    replication.continuous.should.deep.equal params.continuous
                    replication.doc_ids.should.deep.equal params.docIDs
                    # callback mimicks a successful operation
                    callback null, {ok: true, _local_id: 1}

            done()

        after (done) ->
            dbReplicateStub.restore()
            done()


        it 'should return an error when params is missing/empty', (done) ->
            _params = {}

            Sharing.replicateDocs _params, (err) ->
                err.should.deep.equal error
                done()

        it 'should return an error when params.target is missing/empty',
        (done) ->
            _params        = _.cloneDeep params
            _params.target = {}

            Sharing.replicateDocs _params, (err) ->
                err.should.deep.equal error
                done()

        it 'should return an error when params.docIDs is missing/empty',
        (done) ->
            _params        = _.cloneDeep params
            _params.docIDs = null

            Sharing.replicateDocs _params, (err) ->
                err.should.deep.equal error
                done()

        it 'should return an error when params.id is missing/empty', (done) ->
            _params    = _.cloneDeep params
            _params.id = undefined

            Sharing.replicateDocs _params, (err) ->
                err.should.deep.equal error
                done()

        it 'should send the correct replication structure', (done) ->
            Sharing.replicateDocs params, (err) ->
                # nothing to do here: all tests are inside the stub defined in
                # the before hook
                done()

        it 'should return an error when `db.replicate` fails', (done) ->
            dbReplicateStub.restore() # cancel default stub
            dbReplicateError = new Error "db.replicate"
            dbReplicateStub = sinon.stub db, 'replicate',
                (target, replication, callback) ->
                    callback dbReplicateError, null

            Sharing.replicateDocs params, (err) ->
                err.should.deep.equal dbReplicateError
                done()

        it 'should return an error when the replication fails i.e. `body.ok` is
        false', (done) ->
            dbReplicateStub.restore() # cancel previous stub
            replicationError = new Error "Replication failed"
            dbReplicateStub = sinon.stub db, 'replicate',
                (target, replication, callback) ->
                    callback null, {ok: false, _local_id: -1}

            Sharing.replicateDocs params, (err) ->
                err.should.deep.equal replicationError
                done()


    describe 'cancelReplication module', ->

        # parameter required by the module
        replicationID = 'replicationID'

        # stub and hooks
        dbReplicateStub = {}

        before (done) ->
            dbReplicateStub = sinon.stub db, "replicate",
                (target, cancel, callback) ->
                    cancel.replication_id.should.deep.equal replicationID
                    cancel.cancel.should.be.true
                    target.should.be.empty
                    # mimicks a successful cancel
                    callback null, {ok: true}
            done()

        after (done) ->
            dbReplicateStub.restore()
            done()

        it 'should return an error when the replicationID is missing', (done) ->
            error        = new Error "Parameters missing"
            error.status = 400

            Sharing.cancelReplication null, (err) ->
                err.should.deep.equal error
                done()

        it 'should send the correct cancel structure', (done) ->
            Sharing.cancelReplication replicationID, (err) ->
                # nothing to do: tests are defined in the stub
                done()

        it 'should return an error when `db.replicate` fails', (done) ->
            dbReplicateStub.restore() # cancel hook stub
            dbReplicateError = new Error 'db.replicate'
            # replace stub
            dbReplicateStub  = sinon.stub db, "replicate",
                (target, cancel, callback) ->
                    callback dbReplicateError, null

            Sharing.cancelReplication replicationID, (err) ->
                err.should.deep.equal dbReplicateError
                done()

        it 'should return an error when the cancel fails i.e. `body.ok` is
        false', (done) ->
            dbReplicateStub.restore() # cancel previous stub
            replicationError = new Error 'Cancel replication failed'
            # replace stub
            dbReplicateStub  = sinon.stub db, "replicate",
                (target, cancel, callback) ->
                    callback null, {ok: false}

            Sharing.cancelReplication replicationID, (err) ->
                err.should.deep.equal replicationError
                done()

