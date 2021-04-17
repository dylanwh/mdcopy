//
//  main.swift
//  mdcopy
//
//  Created by Dylan Hardison on 2021-04-12.
//

import Foundation
import class AppKit.NSPasteboard
import ArgumentParser
import Maaku

let TransientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

enum TextFormat: String, ExpressibleByArgument {
    case raw, text, markdown
}

struct mdcopy: ParsableCommand {
    @Flag(name: .shortAndLong, help: "Enable smart quotes")
    var smartQuotes: Bool = false
    
    
    @Option(name: .shortAndLong, help: "Format of clipboard plain text version")
    var format: TextFormat = .raw
    
    @Option(name: .shortAndLong, help: "Text width")
    var width: Int32 = 80
    
    @Argument(help: "input file")
    var inputFile: String?

    mutating func run() throws {
        let markdown = try readInput()
        setClipboard(html: try renderHtml(markdown), text: try renderText(markdown))
    }
    
    func markdownOptions() -> CMDocumentOption {
        let options: CMDocumentOption = [.default, .unsafe, .preLang, .strikethroughDoubleTilde]
        if smartQuotes {
            return options.union( .smart )
        }
        else {
            return options
        }
    }
    
    func renderHtml(_ text: Data) throws -> String {
        let doc = try CMDocument(data: text, options: markdownOptions())
        return try doc.renderHtml()
    }
    
    func renderText(_ text: Data) throws -> String {
        let doc = try CMDocument(data: text, options: markdownOptions())
        
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
        pb.setString("<meta charset=\"UTF-8\">" + html, forType: .html)
        pb.setString(text, forType: .string)
        pb.setString("", forType: TransientType)
    }
    
    func readInput() throws -> Data {
        if let file = inputFile {
            let fileUrl = URL(fileURLWithPath: file)
            return slurp(try FileHandle(forReadingFrom: fileUrl))
        }
        else {
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





