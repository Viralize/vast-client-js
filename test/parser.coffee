should = require 'should'
path = require 'path'
VASTParser = require '../src/parser'
VASTResponse = require '../src/response'

NoAdsResponseAfterWrapper = require('../src/error').NoAdsResponseAfterWrapper
TimeoutVastUri = require('../src/error').TimeoutVastUri
SchemaValidationError = require('../src/error').SchemaValidationError
WrapperLimitReached = require('../src/error').WrapperLimitReached


urlfor = (relpath) ->
    return 'file://' + path.resolve(path.dirname(module.filename), 'fixtures/' + relpath).replace(/\\/g, '/')

describe 'VASTParser', ->
    describe '#parse', ->
        @response = null
        _response = null
        @templateFilterCalls = []
        parser = null

        before (done) =>
            parser = new VASTParser()
            parser.addURLTemplateFilter (url) =>
              @templateFilterCalls.push url
              return url
            parser.parse urlfor('wrapper.xml'), (@response) =>
                _response = @response
                done()

        after () =>
            parser.clearUrlTemplateFilters()

        it 'should have 1 filter defined', =>
            parser.countURLTemplateFilters().should.equal 1

        it 'should have called URLtemplateFilter twice', =>
            @templateFilterCalls.should.have.length 2
            @templateFilterCalls.should.eql [urlfor('wrapper.xml'), urlfor('sample.xml')]

        it 'should have found 2 ads', =>
            _response.ads.should.have.length 2

        it 'should have returned a VAST response object', =>
            _response.should.be.an.instanceOf(VASTResponse)

        it 'should have merged top level error URLs', =>
            _response.errorURLTemplates.should.eql ["http://example.com/wrapper-error", "http://example.com/error"]

        it 'should have an empty array for Extensions', =>
            _response.extensionElements.should.eql []

        describe '#For the 1st ad (Wrapped)', ->
            ad1 = null

            before () =>
                ad1 = _response.ads[0]

            after () =>
                ad1 = null

            it 'should have retrieved Ad id attribute', ->
                ad1.id.should.eql "ad_id_0001"

            it 'should have retrieved Ad sequence attribute', ->
                ad1.sequence.should.eql "1"

            it 'should have retrieved AdSystem value', ->
                ad1.system.value.should.eql "AdServer"

            it 'should have retrieved AdSystem version attribute', ->
                ad1.system.version.should.eql "2.0"

            it 'should have retrieved AdTitle value', ->
                ad1.title.should.eql "Ad title"

            it 'should have retrieved Advertiser value', ->
                ad1.advertiser.should.eql "Advertiser name"

            it 'should have retrieved Description value', ->
                ad1.description.should.eql "Description text"

            it 'should have retrieved Pricing value', ->
                ad1.pricing.value.should.eql "1.09"

            it 'should have retrieved Pricing model attribute', ->
                ad1.pricing.model.should.eql "CPM"

            it 'should have retrieved Pricing currency attribute', ->
                ad1.pricing.currency.should.eql "USD"

            it 'should have merged wrapped ad error URLs', =>
                ad1.errorURLTemplates.should.eql ["http://example.com/wrapper-error", "http://example.com/error"]

            it 'should have merged impression URLs', =>
                ad1.impressionURLTemplates.should.eql ["http://example.com/wrapper-impression", "http://127.0.0.1:8080/second/wrapper_impression", "http://example.com/impression1", "http://example.com/impression2", "http://example.com/impression3"]

            it 'should have two creatives', =>
                ad1.creatives.should.have.length 2

        describe '#For the 2nd ad (Non wrapped)', ->
            ad2 = null

            before () =>
                ad2 = _response.ads[1]

            after () =>
                ad2 = null

            it 'should have retrieved Ad attributes', =>
                ad2.id.should.eql "ad_id_0002"
                should.equal ad2.sequence, null

            it 'should have retrieved Ad sub-elements values', =>
                ad2.system.value.should.eql "AdServer2"
                ad2.system.version.should.eql "2.1"
                ad2.title.should.eql "Ad title 2"
                should.equal ad2.advertiser, null
                should.equal ad2.description, null
                should.equal ad2.pricing, null
                should.equal ad2.survey, null

            it 'should have 0 error URL', =>
                ad2.errorURLTemplates.should.eql []

            it 'should have 1 impression URL', =>
                ad2.impressionURLTemplates.should.eql ["http://example.com/impression1"]

            it 'should have 1 creative', =>
                ad2.creatives.should.have.length 1

        #Linear
        describe '#Linear', ->
            linear = null

            before (done) =>
                linear = _response.ads[0].creatives[0]
                done()

            it 'should have linear type', =>
                linear.type.should.equal "linear"

            it 'should have 1 media file', =>
                linear.mediaFiles.should.have.length 1

            it 'should have a duration of 90.123s', =>
                linear.duration.should.equal 90.123

            # Allowed empty duration
            it 'should set duration at 1 if empty', ->
                parser.parse urlfor('empty-duration.xml'), (response) =>
                    response.ads[0].creatives[0].duration.should.equal 1

            it 'should have parsed media file attributes', =>
                mediaFile = linear.mediaFiles[0]
                mediaFile.width.should.equal 512
                mediaFile.height.should.equal 288
                mediaFile.mimeType.should.equal "video/mp4"
                mediaFile.fileURL.should.equal "http://example.com/asset.mp4"

            it 'should have 8 tracking events', =>
                linear.trackingEvents.should.have.keys 'start', 'close', 'midpoint', 'complete', 'firstQuartile', 'thirdQuartile', 'progress-30', 'progress-60%'

            it 'should have 2 urls for start event', =>
                linear.trackingEvents['start'].should.eql ['http://example.com/start', 'http://example.com/wrapper-start']

            it 'should have 2 urls for complete event', =>
                linear.trackingEvents['complete'].should.eql ['http://example.com/complete', 'http://example.com/wrapper-complete']

            it 'should have 1 url for clickthrough', =>
                linear.videoClickThroughURLTemplate.should.eql 'http://example.com/clickthrough'

            it 'should have 2 urls for clicktracking', =>
                linear.videoClickTrackingURLTemplates.should.eql ['http://example.com/clicktracking', 'http://example.com/wrapper-clicktracking']

            it 'should have 1 url for customclick', =>
                linear.videoCustomClickURLTemplates.should.eql ['http://example.com/customclick']

            it 'should have 2 urls for progress-30 event VAST 3.0', =>
                linear.trackingEvents['progress-30'].should.eql ['http://example.com/progress-30sec', 'http://example.com/wrapper-progress-30sec']

            it 'should have 2 urls for progress-60% event VAST 3.0', =>
                linear.trackingEvents['progress-60%'].should.eql ['http://example.com/progress-60%', 'http://example.com/wrapper-progress-60%']

        #Companions
        describe '#Companions', ->
            companions = null

            before (done) =>
                companions = _response.ads[0].creatives[1]
                done()

            it 'should have companion type', =>
                companions.type.should.equal "companion"

            it 'should have 3 variations', =>
                companions.variations.should.have.length 3

            #Companion
            describe '#Companion', ->
                companion = null

                describe 'as image/jpeg', ->
                    before (done) =>
                        companion = companions.variations[0]
                        done()

                    it 'should have parsed size and type attributes', =>
                        companion.width.should.equal '300'
                        companion.height.should.equal '60'
                        companion.type.should.equal 'image/jpeg'

                    it 'should have 1 tracking event', =>
                        companion.trackingEvents.should.have.keys 'creativeView'

                    it 'should have 1 url for creativeView event', =>
                        companion.trackingEvents['creativeView'].should.eql ['http://example.com/creativeview']

                    it 'should have 1 companion clickthrough url', =>
                        companion.companionClickThroughURLTemplate.should.equal  'http://example.com/companion-clickthrough'

                    it 'should have 1 companion clicktracking url', =>
                        companion.companionClickTrackingURLTemplate.should.equal  'http://example.com/companion-clicktracking'

                describe 'as IFrameResource', ->
                  before (done) =>
                      companion = companions.variations[1]
                      done()

                  it 'should have parsed size and type attributes', =>
                      companion.width.should.equal '300'
                      companion.height.should.equal '60'
                      companion.type.should.equal 0

                  it 'does not have tracking events', =>
                    companion.trackingEvents.should.be.empty

                  it 'has the #iframeResource set', ->
                    companion.iframeResource.should.equal 'http://www.example.com/example.php'

                describe 'as text/html', ->
                    before (done) =>
                        companion = companions.variations[2]
                        done()

                    it 'should have parsed size and type attributes', =>
                        companion.width.should.equal '300'
                        companion.height.should.equal '60'
                        companion.type.should.equal 'text/html'

                    it 'should have 1 tracking event', =>
                        companion.trackingEvents.should.be.empty

                    it 'should have 1 companion clickthrough url', =>
                        companion.companionClickThroughURLTemplate.should.equal  'http://www.example.com'

                    it 'has #htmlResource available', ->
                      companion.htmlResource.should.equal "<a href=\"http://www.example.com\" target=\"_blank\">Some call to action HTML!</a>"

        describe '#VAST', ->
            @response = null
            parser = null

            before (done) =>
                parser = new VASTParser()
                parser.parse urlfor('vpaid.xml'), (@response) =>
                    done()

            it 'should have apiFramework set', =>
                @response.ads[0].creatives[0].mediaFiles[0].apiFramework.should.be.equal "VPAID"


    describe '#track errors', ->
        parser = null
        errorCallbackCalled = 0
        errorCode = null
        errorCallback = (errCode) ->
            errorCallbackCalled++
            errorCode = errCode

        beforeEach =>
            parser = new VASTParser()
            parser.vent.removeAllListeners()
            error = null
            errorCallbackCalled = 0

        # No ads VAST response after one wrapper
        it 'emits an VAST-error on empty vast directly', (done) ->
            parser.on 'VAST-error', errorCallback
            parser.parse urlfor('empty.xml'), =>
                errorCallbackCalled.should.equal 1
                errorCode.ERRORCODE.should.eql new NoAdsResponseAfterWrapper().code
                done()

        # # VAST response with Ad but no Creative
        it 'emits a VAST-error on response with no Creative', (done) ->
            parser.on 'VAST-error', errorCallback
            parser.parse urlfor('empty-no-creative.xml'), =>
                errorCallbackCalled.should.equal 1
                errorCode.ERRORCODE.should.eql new NoAdsResponseAfterWrapper().code
                done()

        # No ads VAST response after more than one wrapper
        it 'emits a noAdsResponseAfterWrapper error on empty vast after one wrapper', (done) ->
            parser.on 'VAST-error', errorCallback
            parser.parse urlfor('wrapper-empty.xml'), =>
                errorCallbackCalled.should.equal 2
                errorCode.ERRORCODE.should.eql new NoAdsResponseAfterWrapper().code
                done()

        # Wrapper limit reached after 10 wrapper
        it 'emits a WrapperLimitReached error after 10 wrapper', (done) ->
            parser.on 'VAST-error', errorCallback
            parser.parse urlfor('wrapper-10.xml'), =>
                errorCallbackCalled.should.equal 10
                errorCode.ERRORCODE.should.eql new WrapperLimitReached().code
                done()

    describe '#pass errors in parse callback', ->
        parser = null

        beforeEach =>
            parser = new VASTParser()
            parser.vent.removeAllListeners()

        it 'should send a response obj and a null error if VAST is valid', (done) ->
            parser.parse urlfor('sample.xml'), (response, error) =>
                should.equal error, null
                response.should.have.keys 'ads'
                done()

        it 'should send a null response and a 303 error if VAST is empty', (done) ->
            parser.parse urlfor('empty.xml'), (response, error) =>
                should.equal response, null
                error.code.should.eql 303
                done()

        it 'should send a null response and a 302 error if wrapper length is greater than 10', (done) ->
            parser.parse urlfor('wrapper-10.xml'), (response, error) =>
                should.equal response, null
                error.code.should.eql 302
                done()

        it 'should send a null response and a 303 error if wrapper call is empty', (done) ->
            parser.parse urlfor('wrapper-empty.xml'), (response, error) =>
                should.equal response, null
                error.code.should.eql 303
                done()

        it 'should send a null response and a 101 error if VAST Schema is not valid', (done) ->
            parser.parse urlfor('schema-error.xml'), (response, error) =>
                should.equal response, null
                error.code.should.eql 101
                done()

        it 'should send a null response and a 303 error if no creative', (done) ->
            parser.parse urlfor('empty-no-creative.xml'), (response, error) =>
                should.equal response, null
                error.code.should.eql 303
                done()

    describe '#legacy', ->
        parser = null

        beforeEach =>
            parser = new VASTParser()
            parser.vent.removeAllListeners()

        it 'correctly loads a wrapped ad, even with the VASTAdTagURL-Tag', (done) ->
            parser.parse urlfor('wrapper-legacy.xml'), (response) =>
                it 'should have found 1 ad', =>
                    response.ads.should.have.length 1

                it 'should have returned a VAST response object', =>
                    response.should.be.an.instanceOf(VASTResponse)

                # we just want to make sure that the sample.xml was loaded correctly
                linear = response.ads[0].creatives[0]
                it 'should have parsed media file attributes', =>
                    mediaFile = linear.mediaFiles[0]
                    mediaFile.width.should.equal 512
                    mediaFile.height.should.equal 288
                    mediaFile.mimeType.should.equal "video/mp4"
                    mediaFile.fileURL.should.equal "http://example.com/asset.mp4"

                done()