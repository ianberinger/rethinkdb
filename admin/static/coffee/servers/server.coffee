# Copyright 2010-2015 RethinkDB
# Machine view
# ServerView module

ui_modals = require('../ui_components/modals.coffee')
log_view = require('../log_view.coffee')
server_profile = require('./profile.coffee')
vis = require('../vis.coffee')
models = require('../models.coffee')
app = require('../app.coffee')
driver = app.driver
system_db = app.system_db

r = require('rethinkdb')

class ServerContainer extends Backbone.View
    template:
        error: require('../../handlebars/error-query.hbs')
        not_found: require('../../handlebars/element_view-not_found.hbs')

    initialize: (id) =>
        @id = id
        @server_found = true

        # Initialize with dummy data so we can start rendering the page
        @main_view_model = new Backbone.Model(id: @id)
        @profile_model = new Backbone.Model()
        @server_view = new ServerMainView
            model: @main_view_model
            profile_model: @profile_model

        @fetch_server()

    fetch_server: =>
        query = r.do(
            r.db(system_db).table('server_config').get(@id),
            r.db(system_db).table('server_status').get(@id),
            (server_config, server_status) ->
                profile: server_profile.Profile.query(server_config, server_status)
                main_view: ServerMainView.query(server_status)
        )

        @timer = driver.run query, 5000, (error, result) =>
            # We should call render only once to avoid blowing all the sub views
            if error?
                @error = error
                @render()
            else
                rerender = @error?
                @error = null
                if result is null
                    rerender = rerender or @server_found
                    @server_found = false
                else
                    rerender = rerender or not @server_found
                    @server_found = true
                    @profile_model.set result.profile
                    @main_view_model.set result.main_view
                if rerender
                    @render()

    render: =>
        if @error?
            @$el.html @template.error
                error: @error?.message
                url: '#servers/'+@id
        else
            if @server_found
                @$el.html @server_view.render().$el
            else # The server wasn't found
                @$el.html @template.not_found
                    id: @id
                    type: 'server'
                    type_url: 'servers'
                    type_all_url: 'servers'
        @

    remove: =>
        driver.stop_timer @timer
        @server_view?.remove()
        super()

class ServerMainView extends Backbone.View
    @query: (server_status) ->
        name: server_status('name')
        id: server_status('id')
    template: require('../../handlebars/full_server.hbs')

    events:
        'click .close': 'close_alert'
        'click .operations .rename': 'rename_server'

    rename_server: (event) =>
        event.preventDefault()

        if @rename_modal?
            @rename_modal.remove()
        @rename_modal = new ui_modals.RenameItemModal
            model: @model
        @rename_modal.render()

    # Method to close an alert/warning/arror
    close_alert: (event) ->
        event.preventDefault()
        $(event.currentTarget).parent().slideUp('fast', -> $(this).remove())

    initialize: (options) =>
        @profile_model = options.profile_model

        @profile = new server_profile.Profile
            model: @profile_model
            collection: @collection

        @stats = new models.Stats
        @stats_timer = driver.run(
            r.db(system_db).table('stats')
            .get(['server', @model.get('id')])
            .do((stat) ->
                keys_read: stat('query_engine')('read_docs_per_sec'),
                keys_set: stat('query_engine')('written_docs_per_sec'),
            ), 1000, @stats.on_result)

        @performance_graph = new vis.OpsPlot(@stats.get_stats,
            width:  564             # width in pixels
            height: 210             # height in pixels
            seconds: 73             # num seconds to track
            type: 'server'
        )

    render: =>
        console.log @model.toJSON()
        @$el.html @template(@model.toJSON())

        @$('.profile').html @profile.render().$el
        @$('.performance-graph').html @performance_graph.render().$el
        @logs = new log_view.LogsContainer
            server_id: @model.get('id')
            limit: 5
            query: driver.queries.server_logs
        @$('.recent-log-entries').html @logs.render().$el
        @

    remove: =>
        driver.stop_timer @stats_timer
        @profile.remove()
        if @rename_modal?
            @rename_modal.remove()
        @logs.remove()

exports.ServerContainer = ServerContainer
exports.ServerMainView = ServerMainView
