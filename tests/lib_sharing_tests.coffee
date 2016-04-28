should    = require('chai').Should()
helpers   = require('./helpers')
sinon     = require 'sinon'
_         = require 'lodash'
rewire    = require 'rewire'
httpMocks = require 'node-mocks-http'

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

