VASTParser = require './parser'
VASTUtil = require './util'
UndefinedError = require('./error').UndefinedError

class VASTClient
    @cappingFreeLunch: 0
    @cappingMinimumTimeInterval: 0
    @options:
        withCredentials : false,
        timeout : 0

    @get: (url, opts, cb) ->
        now = +new Date()

        extend = exports.extend = (object, properties) ->
            obj = {}
            for key, val of object
                obj[key] = val
            for key, val of properties
                obj[key] = val
            obj

        if not cb
            cb = opts if typeof opts is 'function'
            options = {}

        options = extend @options, opts

        # Check totalCallsTimeout (first call + 1 hour), if older than now,
        # reset totalCalls number, by this way the client will be eligible again
        # for freelunch capping
        if @totalCallsTimeout < now
            @totalCalls = 1
            @totalCallsTimeout = now + (60 * 60 * 1000)
        else
            @totalCalls++

        if @cappingFreeLunch >= @totalCalls
            cb(null, new UndefinedError())
            return

        timeSinceLastCall = now - @lastSuccessfullAd
        # Check timeSinceLastCall to be a positive number. If not, this mean the
        # previous was made in the future. We reset lastSuccessfullAd value
        if timeSinceLastCall < 0
            @lastSuccessfullAd = 0
        else if timeSinceLastCall < @cappingMinimumTimeInterval
            cb(null, new UndefinedError())
            return

        parser = new VASTParser()
        parser.parse url, options, (response, err) =>
            cb(response, err)


    # 'Fake' static constructor
    do ->
        storage = VASTUtil.storage
        defineProperty = Object.defineProperty

        # Create new properties for VASTClient, using ECMAScript 5
        # we can define custom getters and setters logic.
        # By this way, we implement the use of storage inside these methods,
        # while it will be fully transparent for the user
        ['lastSuccessfullAd', 'totalCalls', 'totalCallsTimeout'].forEach (property) ->
            defineProperty VASTClient, property,
            {
                get: () -> storage.getItem property
                set: (value) -> storage.setItem property, value
                configurable: false
                enumerable: true
            }
            return

        # Init values if not already set
        VASTClient.lastSuccessfullAd ?= 0
        VASTClient.totalCalls ?= 0
        VASTClient.totalCallsTimeout ?= 0
        return

module.exports = VASTClient