//
//  main.swift
//  mdcopy
//
//  Created by Dylan Hardison on 2021-04-12.
//

import Foundation
import class AppKit.NSPasteboard


import func cmark.cmark_gfm_markdown_to_html
import var cmark.CMARK_OPT_SMART
import var cmark.CMARK_OPT_DEFAULT
import var cmark.CMARK_OPT_GITHUB_PRE_LANG

let TransientType = NSPasteboard.PasteboardType.init("org.nspasteboard.TransientType")

let pb = NSPasteboard.general
let text = FileHandle.standardInput.availableData
let html = markdown(text)

pb.prepareForNewContents(with: NSPasteboard.ContentsOptions.init())
pb.clearContents()
pb.setData(text, forType: NSPasteboard.PasteboardType.string)
pb.setData(html ?? text, forType: NSPasteboard.PasteboardType.html)
pb.setData(Data.init(), forType: TransientType)


func markdown(_ text: Data) -> Data? {
    let opts = CMARK_OPT_DEFAULT | CMARK_OPT_GITHUB_PRE_LANG | CMARK_OPT_SMART
    let text_bytes: [Int8] = [UInt8](text).map {Int8(bitPattern: $0)}
    guard let html_bytes = cmark_gfm_markdown_to_html(text_bytes, text.count, opts) else {
        return nil
    }
    
    let html = String(cString: html_bytes).data(using: String.Encoding.utf8)
    html_bytes.deallocate()
    return html
}
