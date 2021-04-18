//
//  main.swift
//  mdcopy
//
//  Created by Dylan Hardison on 2021-04-12.
//

import ArgumentParser
import Foundation
import Maaku

import class AppKit.NSPasteboard

let TransientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

struct mdcopy: ParsableCommand {

  enum TextFormat: String, ExpressibleByArgument {
    case raw, text, markdown
  }

  @Flag(name: .shortAndLong, help: "Enable smart quotes")
  var smartQuotes: Bool = false

  @Flag(name: .shortAndLong, help: "Mark pasteboard with transient hint")
  var transient: Bool = false

  @Option(name: .shortAndLong, help: "Text format of plain text pasteboard variant")
  var format: TextFormat = .raw

  @Option(name: .shortAndLong, help: "Text width")
  var width: Int32 = 80

  @Option(name: .shortAndLong, help: "Input string")
  var input: String?

  @Argument(help: "input file")
  var inputFile: String?

  mutating func run() throws {
    let markdown = try readInput()
    setClipboard(html: try renderHtml(markdown), text: try renderText(markdown))
  }

  func parse(markdown: Data) throws -> CMDocument {
    let extensions: CMExtensionOption = .all
    var options: CMDocumentOption = [.default, .unsafe, .preLang, .strikethroughDoubleTilde]
    if smartQuotes {
      options.insert(.smart)
    }

    return try CMDocument(
      text: String(data: markdown, encoding: .utf8)!,
      options: options,
      extensions: extensions)
  }

  func renderHtml(_ text: Data) throws -> String {
    let doc = try parse(markdown: text)
    return try doc.renderHtml()
  }

  func renderText(_ text: Data) throws -> String {
    let doc = try parse(markdown: text)

    switch format {
    case .raw:
      return String(data: text, encoding: .utf8)!
    case .markdown:
      return try doc.renderCommonMark(width: width)
    case .text:
      var currentLink: URL?
      try doc.node.iterator?.enumerate {
        (node: CMNode, event: CMEventType) -> Bool in
        switch (event, node.type) {
        case (.enter, .link):
          currentLink = node.linkUrl
        case (.enter, .text):
          if let link = currentLink {
            try node.setLiteral(link.absoluteString)
          }
        default:
          break
        }
        return false
      }
      return try doc.renderPlainText(width: width)
    }
  }

  func setClipboard(html: String, text: String) {
    let pb = NSPasteboard.general
    pb.prepareForNewContents(with: NSPasteboard.ContentsOptions())
    pb.clearContents()
    /* without the meta, this will be interpreted as latin1! */
    pb.setString("<meta charset=\"UTF-8\">" + html, forType: .html)
    pb.setString(text, forType: .string)
    if transient {
      pb.setString("", forType: TransientType)
    }
  }

  func readInput() throws -> Data {
    if let file = inputFile {
      let fileUrl = URL(fileURLWithPath: file)
      let fileHandle = try FileHandle(forReadingFrom: fileUrl)
      return slurp(fileHandle)
    } else if let text = input {
      return text.data(using: .utf8, allowLossyConversion: true)!
    } else {
      return slurp(FileHandle.standardInput)
    }
  }

  func slurp(_ fh: FileHandle) -> Data {
    var chunk: Data
    var input = Data()
    repeat {
      chunk = fh.availableData
      input.append(chunk)
    } while chunk.count > 0
    return input
  }
}

mdcopy.main()
