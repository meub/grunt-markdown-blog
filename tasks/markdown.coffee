###
Task: markdown
Description: generates HTML files from markdown files for static deployment
Dependencies: grunt, marked
Contributor: @searls
###

marked = require('marked')
_ = require('underscore')
fs = require('fs')
highlight = require('highlight.js')
grunt = require('grunt')
moment = require('moment')
pathlib = require('path')

marked.setOptions
  highlight: (code, lang) ->
    highlighted = if highlight.LANGUAGES[lang]?
      highlight.highlight(lang, code, true)
    else
      highlight.highlightAuto(code)
    highlighted.value


module.exports = (grunt) ->
  grunt.registerMultiTask "markdown", "generates HTML from markdown", ->
    config = _(
      author: "Full Name"
      title: "my blog"
      description: "the blog where I write things"
      url: "http://www.myblog.com"
      # disqus: "agile" #<-- define a disqus name for use in your templates
      rssCount: 10
      layouts:
        wrapper: "app/templates/wrapper.us"
        index: "app/templates/index.us"
        post: "app/templates/post.us"
        page: "app/templates/page.us"
        archive: "app/templates/archive.us"
      paths:
        posts: "posts/*.md"
        pages: "pages/**/*.md"
        index: "index.html"
        archive: "archive.html"
        rss: "index.xml"
      dest: "dist"
      context:
        js: "app.js"
        css: "app.css"
    ).extend(@options(@data))
    new MarkdownTask(config).run()

class MarkdownTask
  constructor: (@config) ->
    @writesFile = new WritesFile(@config.dest)
    @site = new Site(@config, @buildPosts(), new Layout(@config.layouts.post))
    @site.addPages(@buildPages(), new Layout(@config.layouts.page)) if @config.layouts.page?
    @wrapper = new Layout(@config.layouts.wrapper, @config.context)

  run: ->
    @createPosts()
    if @config.layouts.page?
      @createPages()
    @createIndex()
    @createArchive()
    @createRss()

  createPosts: ->
    generatesHtml = new GeneratesHtml(@wrapper, new Layout(@config.layouts.post), @site)
    _(@site.posts).each (post) =>
      html = generatesHtml.generate(post)
      @writesFile.write(html, post.htmlPath())

  createPages: ->
    generatesHtml = new GeneratesHtml(@wrapper, new Layout(@config.layouts.page), @site)
    _(@site.pages).each (page) =>
      html = generatesHtml.generate(page)
      @writesFile.write(html, page.htmlPath())

  createIndex: ->
    html = new GeneratesHtml(@wrapper, new Layout(@config.layouts.index), @site).generate()
    @writesFile.write(html, @config.paths.index)

  createArchive: ->
    html = new GeneratesHtml(@wrapper, new Layout(@config.layouts.archive), @site).generate()
    @writesFile.write(html, @config.paths.archive)

  createRss: ->
    return unless @site.paths.rss? && @site.rssCount
    rss = new GeneratesRss(@site).generate()
    @writesFile.write(rss, @site.paths.rss)

  buildPosts: ->
    _(@allMarkdownPosts()).map (markdownPath) =>
      new Post(markdownPath, @config.paths.posts)

  buildPages: ->
    if @config.paths.pages
      _(@allMarkdownPages()).map (markdownPath) =>
        new Page(markdownPath, @config.paths.pages)

  #private
  allMarkdownPosts: -> grunt.file.expand(@config.paths.posts)
  allMarkdownPages: -> grunt.file.expand(@config.paths.pages)

class GeneratesHtml
  constructor: (@wrapper, @template, @site) ->

  generate: (post) ->
    context = site: @site, post: post
    context.yield = @template.htmlFor(context)
    @wrapper.htmlFor(context)

class GeneratesRss
  constructor: (@site) ->
    @Rss = require('rss')

  generate: ->
    feed = @createFeed()
    @addPostsTo(feed)
    feed.xml()

  createFeed: ->
    new @Rss
      title: @site.title
      description: @site.description
      feed_url: "#{@site.url}/#{@site.paths.rss}"
      site_url: @site.url
      author: @site.author

  addPostsTo: (feed) ->
    _(@site.posts).chain().first(@site.rssCount).each (post) =>
      feed.item
        title: post.title()
        description: post.content()
        url: @site.urlFor(post)
        date: post.time()


class WritesFile
  constructor: (@dest) ->

  write: (content, filePath) ->
    path = "#{@dest}/#{filePath}"
    grunt.log.writeln("Writing #{content.length} characters to #{path}")
    grunt.file.write(path, content)

class Layout
  constructor: (layoutPath, context = {}) ->
    @layout = _(grunt.file.read(layoutPath)).template()
    @context = context

  htmlFor: (specificContext) ->
    @layout(_(@context).extend(specificContext))

#--- models the site

class Site
  constructor: (config, posts, @postLayout) ->
    _(@).extend(config)
    @posts = _(posts).sortBy (p) -> p.fileName()

  addPages: (@pages, @pageLayout) ->

  olderPost: (post) ->
    return if _(@posts).first() == post
    @posts[_(@posts).indexOf(post) - 1]

  newerPost: (post) ->
    return if _(@posts).last() == post
    @posts[_(@posts).indexOf(post) + 1]

  htmlFor: (post) ->
    @postLayout.htmlFor(post: post, site: this)

  urlFor: (post) ->
    "#{@url}/#{post.htmlPath()}"


class Page
  constructor: (@path, @htmlDirPath) ->

  content: ->
    markdown = grunt.file.read(@path)
    content = marked.parser(marked.lexer(markdown))

  title: ->
    dasherized = @path.match(/\/\d{4}-\d{2}-\d{2}-([^/]*).md/)?[1]
    title = dasherized?.replace(/-/g, " ")
    title || @fileName()

  htmlPath: ->
    pathlib.join(@path.replace('.md', '.html'))

  fileName: ->
    name = @path.match(/\/([^/]*).md/)?[1]
    "#{name}.html"

class Post extends Page
  date: ->
    if date = @time()
      moment(date).format('MMMM Do YYYY').toLowerCase()

  time: ->
    @path.match(/\/(\d{4}-\d{2}-\d{2})/)?[1]
