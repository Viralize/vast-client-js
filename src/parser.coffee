URLHandler = require './urlhandler'
VASTResponse = require './response'
VASTAd = require './ad'
VASTUtil = require './util'
VASTCreativeLinear = require('./creative').VASTCreativeLinear
VASTCreativeCompanion = require('./creative').VASTCreativeCompanion
VASTMediaFile = require './mediafile'
VASTCompanionAd = require './companionad'

SchemaValidationError = require('./error').SchemaValidationError
NoAdsResponseAfterWrapper = require('./error').NoAdsResponseAfterWrapper
WrapperLimitReached = require('./error').WrapperLimitReached
TimeoutVastUri = require('./error').TimeoutVastUri
EventEmitter = require('events').EventEmitter

class VASTParser

    constructor: ->
        @URLTemplateFilters = []
        @xmlLists = []
        @urlLists = []
        @trackingEvents = []
        @trackingClicks = []
        @extensionElements = []
        @impressions = []
        @vent = new EventEmitter()
        @error = null

    addURLTemplateFilter: (func) ->
        @URLTemplateFilters.push(func) if typeof func is 'function'
        return

    removeURLTemplateFilter: () -> @URLTemplateFilters.pop()
    countURLTemplateFilters: () -> @URLTemplateFilters.length
    clearUrlTemplateFilters: () -> @URLTemplateFilters = []

    parse: (url, options, cb) ->
        if not cb
            cb = options if typeof options is 'function'
            options = {}

        @_parse url, null, options, (err, response) ->
            cb(response, err)

    track: (templates, errorCode) ->
        @vent.emit 'VAST-error', errorCode
        VASTUtil.track(templates, errorCode)

    on: (eventName, cb) ->
        @vent.on eventName, cb

    once: (eventName, cb) ->
        @vent.once eventName, cb

    _parse: (url, parentURLs, options, cb) ->
        # Options param can be skipped
        if not cb
            cb = options if typeof options is 'function'
            options = {}

        # Process url with defined filter
        url = filter(url) for filter in @URLTemplateFilters

        parentURLs ?= []
        parentURLs.push url

        URLHandler.get url, options, (err, xml) =>
            return cb(err) if err?

            response = new VASTResponse()

            unless xml?.documentElement? and xml.documentElement.nodeName is "VAST"
                @error = new SchemaValidationError()
                return cb(@error, null)

            for node in xml.documentElement.childNodes
                if node.nodeName is 'Error'
                    response.errorURLTemplates.push (@parseNodeText node)

            for node in xml.documentElement.childNodes
                if node.nodeName is 'Ad'
                    ad = @parseAdElement node
                    if ad?
                        response.ads.push ad
                    else
                        @error = new SchemaValidationError()
                        @track(response.errorURLTemplates, ERRORCODE: @error.code)

            complete = (error = null, errorAlreadyRaised = false) =>
                return unless response
                noCreatives = true
                for ad in response.ads
                    return if ad.nextWrapperURL?
                    if ad.creatives.length > 0
                        noCreatives = false
                if noCreatives
                    # No Ad Response
                    # The VAST <Error> element is optional but if included, the video player must send a request to the URI
                    # provided when the VAST response returns an empty InLine response after a chain of one or more wrapper ads.
                    # If an [ERROR] macro is included, the video player should substitute with error code 303.
                    if not error?
                        @error = error = new NoAdsResponseAfterWrapper()
                        @track(response.errorURLTemplates, ERRORCODE: @error.code) unless errorAlreadyRaised
                        response.ads = []
                if response.ads.length == 0
                    response = null
                else
                    @xmlLists.push xml
                    @urlLists.push url
                    response.docxml = @xmlLists[0]
                    response.lasturl = @urlLists[0]
                    response.impressions = @impressions
                    response.trackingClicks = @trackingClicks
                    response.trackingEvents = @trackingEvents
                    response.extensionElements = @extensionElements
                cb(error, response)

            loopIndex = response.ads.length
            while loopIndex--
                ad = response.ads[loopIndex]
                continue unless ad.nextWrapperURL?
                do (ad) =>
                    if parentURLs.length >= 10 or ad.nextWrapperURL in parentURLs
                        # Wrapper limit reached, as defined by the video player.
                        # Too many Wrapper responses have been received with no InLine response.

                        @error = new WrapperLimitReached()
                        @track(ad.errorURLTemplates, ERRORCODE: @error.code)
                        response.ads.splice(response.ads.indexOf(ad), 1)
                        complete(@error)
                        return

                    if ad.nextWrapperURL.indexOf('//') == 0
                      protocol = location.protocol
                      ad.nextWrapperURL = "#{protocol}#{ad.nextWrapperURL}"
                    else if ad.nextWrapperURL.indexOf('://') == -1
                        # Resolve relative URLs (mainly for unit testing)
                        baseURL = url.slice(0, url.lastIndexOf('/'))
                        ad.nextWrapperURL = "#{baseURL}/#{ad.nextWrapperURL}"

                    @_parse ad.nextWrapperURL, parentURLs, options, (err, wrappedResponse) =>
                        errorAlreadyRaised = false
                        if err?
                            # Timeout of VAST URI provided in Wrapper element, or of VAST URI provided in a subsequent Wrapper element.
                            # (URI was either unavailable or reached a timeout as defined by the video player.)

                            @error = err || new TimeoutVastUri()
                            @track(ad.errorURLTemplates, ERRORCODE: @error.code)
                            response.ads.splice(response.ads.indexOf(ad), 1)
                            errorAlreadyRaised = true
                        else if not wrappedResponse?
                            # No Ads VAST response after one or more Wrappers

                            @error = err || new NoAdsResponseAfterWrapper()
                            @track(ad.errorURLTemplates, ERRORCODE: @error.code)
                            response.ads.splice(response.ads.indexOf(ad), 1)
                            errorAlreadyRaised = true
                        else
                            response.errorURLTemplates = response.errorURLTemplates.concat wrappedResponse.errorURLTemplates
                            index = response.ads.indexOf(ad)
                            response.ads.splice(index, 1)
                            for wrappedAd in wrappedResponse.ads
                                wrappedAd.errorURLTemplates = ad.errorURLTemplates.concat wrappedAd.errorURLTemplates
                                wrappedAd.impressionURLTemplates = ad.impressionURLTemplates.concat wrappedAd.impressionURLTemplates
                                @impressions.push 'url': url, 'obj': ad.impressionURLTemplates

                                if ad.trackingEvents?
                                    for creative in wrappedAd.creatives
                                        if creative.type is 'linear'
                                            for eventName in Object.keys ad.trackingEvents
                                                creative.trackingEvents[eventName] or= []
                                                creative.trackingEvents[eventName] = creative.trackingEvents[eventName].concat ad.trackingEvents[eventName]
                                            @trackingEvents.push 'url': url, 'obj': ad.trackingEvents

                                if ad.videoClickTrackingURLTemplates?
                                    for creative in wrappedAd.creatives
                                        if creative.type is 'linear'
                                            creative.videoClickTrackingURLTemplates = creative.videoClickTrackingURLTemplates.concat ad.videoClickTrackingURLTemplates
                                            @trackingClicks.push 'url': url, 'obj': ad.videoClickTrackingURLTemplates

                                if ad.extensions?
                                    @extensionElements.push ad.extensions

                                response.ads.splice index, 0, wrappedAd

                        delete ad.nextWrapperURL
                        complete @error, errorAlreadyRaised

            complete()

    childByName: (node, name) ->
        for child in node.childNodes
            if child.nodeName is name
                return child

    childsByName: (node, name) ->
        childs = []
        for child in node.childNodes
            if child.nodeName is name
                childs.push child
        return childs

    parseAdElement: (adElement) ->
        for adTypeElement in adElement.childNodes
            continue unless adTypeElement.nodeName in ["Wrapper", "InLine"]

            @copyNodeAttribute "id", adElement, adTypeElement
            @copyNodeAttribute "sequence", adElement, adTypeElement

            if adTypeElement.nodeName is "Wrapper"
                return @parseWrapperElement adTypeElement
            else if adTypeElement.nodeName is "InLine"
                return @parseInLineElement adTypeElement

    parseWrapperElement: (wrapperElement) ->
        ad = @parseInLineElement wrapperElement
        wrapperURLElement = @childByName wrapperElement, "VASTAdTagURI"
        if wrapperURLElement?
            ad.nextWrapperURL = @parseNodeText wrapperURLElement
        else
            wrapperURLElement = @childByName wrapperElement, "VASTAdTagURL"
            if wrapperURLElement?
                ad.nextWrapperURL = @parseNodeText @childByName wrapperURLElement, "URL"

        wrapperCreativeElement = null
        for creative in ad.creatives
            if creative.type is 'linear'
                wrapperCreativeElement = creative
                break

        if wrapperCreativeElement?
            if wrapperCreativeElement.trackingEvents?
                ad.trackingEvents = wrapperCreativeElement.trackingEvents
            if wrapperCreativeElement.videoClickTrackingURLTemplates?
                ad.videoClickTrackingURLTemplates = wrapperCreativeElement.videoClickTrackingURLTemplates

        if ad.nextWrapperURL?
            return ad

    parseInLineElement: (inLineElement) ->
        ad = new VASTAd()
        ad.id = inLineElement.getAttribute("id") || null
        ad.sequence = inLineElement.getAttribute("sequence") || null

        for node in inLineElement.childNodes
            switch node.nodeName
                when "Error"
                    ad.errorURLTemplates.push (@parseNodeText node)

                when "Impression"
                    ad.impressionURLTemplates.push (@parseNodeText node)

                # refactor this as soon as possible with official extensions implementation
                when "Extensions"
                    if not node.innerHTML?
                        nodeHtml = ""
                        try
                            s = new XMLSerializer()
                            nodeHtml = s.serializeToString(node)
                        catch e
                            nodeHtml = node.xml
                        finally
                            nodeHtml = nodeHtml.replace('<Extensions>', '').replace('</Extensions>', '').trim()
                            ad.extensions.push nodeHtml

                    else
                        ad.extensions.push node.innerHTML

                when "AdSystem"
                    ad.system =
                        value : @parseNodeText node
                        version : node.getAttribute("version") || null

                when "AdTitle"
                    ad.title = @parseNodeText node

                when "Description"
                    ad.description = @parseNodeText node

                when "Advertiser"
                    ad.advertiser = @parseNodeText node

                when "Pricing"
                    ad.pricing =
                        value    : @parseNodeText node
                        model    : node.getAttribute("model") || null
                        currency : node.getAttribute("currency") || null

                when "Survey"
                    ad.survey = @parseNodeText node

                when "Creatives"
                    for creativeElement in @childsByName(node, "Creative")
                        for creativeTypeElement in creativeElement.childNodes
                            switch creativeTypeElement.nodeName
                                when "Linear"
                                    creative = @parseCreativeLinearElement creativeTypeElement
                                    if creative
                                        ad.creatives.push creative
                                #when "NonLinearAds"
                                    # TODO
                                when "CompanionAds"
                                    creative = @parseCompanionAd creativeTypeElement
                                    if creative
                                        ad.creatives.push creative

        return ad

    parseCreativeLinearElement: (creativeElement) ->
        creative = new VASTCreativeLinear()

        creative.duration = @parseDuration @parseNodeText(@childByName(creativeElement, "Duration"))
        if creative.duration <= 0 and creativeElement.parentNode.parentNode.parentNode.nodeName != 'Wrapper'
            creative.duration = 1

        skipOffset = creativeElement.getAttribute("skipoffset")
        if not skipOffset? then creative.skipDelay = null
        else if skipOffset.charAt(skipOffset.length - 1) is "%"
            percent = parseInt(skipOffset, 10)
            creative.skipDelay = creative.duration * (percent / 100)
        else
            creative.skipDelay = @parseDuration skipOffset

        videoClicksElement = @childByName(creativeElement, "VideoClicks")
        if videoClicksElement?
            creative.videoClickThroughURLTemplate = @parseNodeText(@childByName(videoClicksElement, "ClickThrough"))
            for clickTrackingElement in @childsByName(videoClicksElement, "ClickTracking")
                creative.videoClickTrackingURLTemplates.push @parseNodeText(clickTrackingElement)
            for customClickElement in @childsByName(videoClicksElement, "CustomClick")
                creative.videoCustomClickURLTemplates.push @parseNodeText(customClickElement)

        adParamsElement = @childByName(creativeElement, "AdParameters")
        if adParamsElement?
            creative.adParameters = @parseNodeText(adParamsElement)

        for trackingEventsElement in @childsByName(creativeElement, "TrackingEvents")
            for trackingElement in @childsByName(trackingEventsElement, "Tracking")
                eventName = trackingElement.getAttribute("event")
                trackingURLTemplate = @parseNodeText(trackingElement)
                if eventName? and trackingURLTemplate?
                    if eventName == "progress"
                        offset = trackingElement.getAttribute("offset")
                        if not offset
                            continue
                        if offset.charAt(offset.length - 1) == '%'
                            eventName = "progress-#{offset}"
                        else
                            eventName = "progress-#{Math.round(@parseDuration offset)}"

                    creative.trackingEvents[eventName] ?= []
                    creative.trackingEvents[eventName].push trackingURLTemplate

        for mediaFilesElement in @childsByName(creativeElement, "MediaFiles")
            for mediaFileElement in @childsByName(mediaFilesElement, "MediaFile")
                mediaFile = new VASTMediaFile()
                mediaFile.id = mediaFileElement.getAttribute("id")
                mediaFile.fileURL = @parseNodeText(mediaFileElement)
                mediaFile.deliveryType = mediaFileElement.getAttribute("delivery")
                mediaFile.codec = mediaFileElement.getAttribute("codec")
                mediaFile.mimeType = mediaFileElement.getAttribute("type")
                mediaFile.apiFramework = mediaFileElement.getAttribute("apiFramework")
                mediaFile.bitrate = parseInt mediaFileElement.getAttribute("bitrate") or 0
                mediaFile.minBitrate = parseInt mediaFileElement.getAttribute("minBitrate") or 0
                mediaFile.maxBitrate = parseInt mediaFileElement.getAttribute("maxBitrate") or 0
                mediaFile.width = parseInt mediaFileElement.getAttribute("width") or 0
                mediaFile.height = parseInt mediaFileElement.getAttribute("height") or 0

                scalable = mediaFileElement.getAttribute("scalable")
                if scalable and typeof scalable is "string"
                  scalable = scalable.toLowerCase()
                  if scalable is "true" then mediaFile.scalable = true
                  else if scalable is "false" then mediaFile.scalable = false

                maintainAspectRatio = mediaFileElement.getAttribute("maintainAspectRatio")
                if maintainAspectRatio and typeof maintainAspectRatio is "string"
                  maintainAspectRatio = maintainAspectRatio.toLowerCase()
                  if maintainAspectRatio is "true" then mediaFile.maintainAspectRatio = true
                  else if maintainAspectRatio is "false" then mediaFile.maintainAspectRatio = false

                creative.mediaFiles.push mediaFile

        return creative

    parseCompanionAd: (creativeElement) ->
        creative = new VASTCreativeCompanion()

        for companionResource in @childsByName(creativeElement, "Companion")
            companionAd = new VASTCompanionAd()
            companionAd.id = companionResource.getAttribute("id") or null
            companionAd.width = companionResource.getAttribute("width")
            companionAd.height = companionResource.getAttribute("height")
            for htmlElement in @childsByName(companionResource, "HTMLResource")
                companionAd.type = htmlElement.getAttribute("creativeType") or 'text/html'
                companionAd.htmlResource = @parseNodeText(htmlElement)
            for iframeElement in @childsByName(companionResource, "IFrameResource")
                companionAd.type = iframeElement.getAttribute("creativeType") or 0
                companionAd.iframeResource = @parseNodeText(iframeElement)
            for staticElement in @childsByName(companionResource, "StaticResource")
                companionAd.type = staticElement.getAttribute("creativeType") or 0
                companionAd.staticResource = @parseNodeText(staticElement)
            for trackingEventsElement in @childsByName(companionResource, "TrackingEvents")
                for trackingElement in @childsByName(trackingEventsElement, "Tracking")
                    eventName = trackingElement.getAttribute("event")
                    trackingURLTemplate = @parseNodeText(trackingElement)
                    if eventName? and trackingURLTemplate?
                        companionAd.trackingEvents[eventName] ?= []
                        companionAd.trackingEvents[eventName].push trackingURLTemplate
            companionAd.companionClickThroughURLTemplate = @parseNodeText(@childByName(companionResource, "CompanionClickThrough"))
            companionAd.companionClickTrackingURLTemplate = @parseNodeText(@childByName(companionResource, "CompanionClickTracking"))
            creative.variations.push companionAd

        return creative

    parseDuration: (durationString) ->
        unless (durationString?)
            return -1
        durationComponents = durationString.split(":")
        if durationComponents.length != 3
            return -1

        secondsAndMS = durationComponents[2].split(".")
        seconds = parseInt secondsAndMS[0]
        if secondsAndMS.length == 2
            seconds += parseFloat "0." + secondsAndMS[1]

        minutes = parseInt durationComponents[1] * 60
        hours = parseInt durationComponents[0] * 60 * 60

        if isNaN hours or isNaN minutes or isNaN seconds or minutes > 60 * 60 or seconds > 60
            return -1
        return hours + minutes + seconds

    # Parsing node text for legacy support
    parseNodeText: (node) ->
        return node and (node.textContent or node.text or '').trim()

    copyNodeAttribute: (attributeName, nodeSource, nodeDestination) ->
        attributeValue = nodeSource.getAttribute attributeName
        if attributeValue
            nodeDestination.setAttribute attributeName, attributeValue

module.exports = VASTParser
