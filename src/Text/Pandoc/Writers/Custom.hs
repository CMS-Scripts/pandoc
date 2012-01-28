{-
Copyright (C) 2012 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- |
   Module      : Text.Pandoc.Writers.Custom
   Copyright   : Copyright (C) 2012 John MacFarlane
   License     : GNU GPL, version 2 or above 

   Maintainer  : John MacFarlane <jgm@berkeley.edu>
   Stability   : alpha
   Portability : portable

Conversion of 'Pandoc' documents to custom markup using
a lua writer.
-}
module Text.Pandoc.Writers.Custom ( writeCustom ) where
import Text.Pandoc.Definition
import Text.Pandoc.Shared 
import Text.Pandoc.Templates (renderTemplate)
import Data.List ( intersect, intercalate )

-- | Convert Pandoc to custom markup.
writeCustom :: WriterOptions -> Pandoc -> IO String
writeCustom opts (Pandoc _ blocks) = do
  body <- blockListToCustom opts blocks
  return body

-- | Convert Pandoc block element to Custom.
blockToCustom :: WriterOptions -- ^ Options
              -> Block         -- ^ Block element
              -> IO String

blockToCustom _ Null = return ""

blockToCustom opts (Plain inlines) =
  inlineListToCustom opts inlines

{-
blockToCustom opts (Para [Image txt (src,tit)]) =
  capt <- inlineListToCustom opts txt
  let opt = if null txt
               then ""
               else "|alt=" ++ if null tit then capt else tit ++
                    "|caption " ++ capt
  return "CAPTION-IMAGE"

blockToCustom opts (Para inlines) = do
  useTags <- get >>= return . stUseTags
  listLevel <- get >>= return . stListLevel
  contents <- inlineListToCustom opts inlines
  return $ if useTags
              then  "<p>" ++ contents ++ "</p>"
              else contents ++ if null listLevel then "\n" else ""

blockToCustom _ (RawBlock "mediawiki" str) = return str
blockToCustom _ (RawBlock "html" str) = return str
blockToCustom _ (RawBlock _ _) = return ""

blockToCustom _ HorizontalRule = return "\n-----\n"

blockToCustom opts (Header level inlines) = do
  contents <- inlineListToCustom opts inlines
  let eqs = replicate level '='
  return $ eqs ++ " " ++ contents ++ " " ++ eqs ++ "\n"

blockToCustom _ (CodeBlock (_,classes,_) str) = do
  let at  = classes `intersect` ["actionscript", "ada", "apache", "applescript", "asm", "asp",
                       "autoit", "bash", "blitzbasic", "bnf", "c", "c_mac", "caddcl", "cadlisp", "cfdg", "cfm",
                       "cpp", "cpp-qt", "csharp", "css", "d", "delphi", "diff", "div", "dos", "eiffel", "fortran",
                       "freebasic", "gml", "groovy", "html4strict", "idl", "ini", "inno", "io", "java", "java5",
                       "javascript", "latex", "lisp", "lua", "matlab", "mirc", "mpasm", "mysql", "nsis", "objc",
                       "ocaml", "ocaml-brief", "oobas", "oracle8", "pascal", "perl", "php", "php-brief", "plsql",
                       "python", "qbasic", "rails", "reg", "robots", "ruby", "sas", "scheme", "sdlbasic",
                       "smalltalk", "smarty", "sql", "tcl", "", "thinbasic", "tsql", "vb", "vbnet", "vhdl", 
                       "visualfoxpro", "winbatch", "xml", "xpp", "z80"]
  let (beg, end) = if null at
                      then ("<pre" ++ if null classes then ">" else " class=\"" ++ unwords classes ++ "\">", "</pre>")
                      else ("<source lang=\"" ++ head at ++ "\">", "</source>")
  return $ beg ++ escapeString str ++ end

blockToCustom opts (BlockQuote blocks) = do
  contents <- blockListToCustom opts blocks
  return $ "<blockquote>" ++ contents ++ "</blockquote>" 

blockToCustom opts (Table capt aligns widths headers rows') = do
  let alignStrings = map alignmentToString aligns
  captionDoc <- if null capt
                   then return ""
                   else do
                      c <- inlineListToCustom opts capt
                      return $ "<caption>" ++ c ++ "</caption>\n"
  let percent w = show (truncate (100*w) :: Integer) ++ "%"
  let coltags = if all (== 0.0) widths
                   then ""
                   else unlines $ map
                         (\w -> "<col width=\"" ++ percent w ++ "\" />") widths
  head' <- if all null headers
              then return ""
              else do
                 hs <- tableRowToCustom opts alignStrings 0 headers
                 return $ "<thead>\n" ++ hs ++ "\n</thead>\n"
  body' <- zipWithM (tableRowToCustom opts alignStrings) [1..] rows'
  return $ "<table>\n" ++ captionDoc ++ coltags ++ head' ++
            "<tbody>\n" ++ unlines body' ++ "</tbody>\n</table>\n"

blockToCustom opts x@(BulletList items) = do
  oldUseTags <- get >>= return . stUseTags
  let useTags = oldUseTags || not (isSimpleList x)
  if useTags
     then do
        modify $ \s -> s { stUseTags = True }
        contents <- mapM (listItemToCustom opts) items
        modify $ \s -> s { stUseTags = oldUseTags }
        return $ "<ul>\n" ++ vcat contents ++ "</ul>\n"
     else do
        modify $ \s -> s { stListLevel = stListLevel s ++ "*" }
        contents <- mapM (listItemToCustom opts) items
        modify $ \s -> s { stListLevel = init (stListLevel s) }
        return $ vcat contents ++ "\n"

blockToCustom opts x@(OrderedList attribs items) = do
  oldUseTags <- get >>= return . stUseTags
  let useTags = oldUseTags || not (isSimpleList x)
  if useTags
     then do
        modify $ \s -> s { stUseTags = True }
        contents <- mapM (listItemToCustom opts) items
        modify $ \s -> s { stUseTags = oldUseTags }
        return $ "<ol" ++ listAttribsToString attribs ++ ">\n" ++ vcat contents ++ "</ol>\n"
     else do
        modify $ \s -> s { stListLevel = stListLevel s ++ "#" }
        contents <- mapM (listItemToCustom opts) items
        modify $ \s -> s { stListLevel = init (stListLevel s) }
        return $ vcat contents ++ "\n"

blockToCustom opts x@(DefinitionList items) = do
  oldUseTags <- get >>= return . stUseTags
  let useTags = oldUseTags || not (isSimpleList x)
  if useTags
     then do
        modify $ \s -> s { stUseTags = True }
        contents <- mapM (definitionListItemToCustom opts) items
        modify $ \s -> s { stUseTags = oldUseTags }
        return $ "<dl>\n" ++ vcat contents ++ "</dl>\n"
     else do
        modify $ \s -> s { stListLevel = stListLevel s ++ ";" }
        contents <- mapM (definitionListItemToCustom opts) items
        modify $ \s -> s { stListLevel = init (stListLevel s) }
        return $ vcat contents ++ "\n"

-- Auxiliary functions for lists:

-- | Convert ordered list attributes to HTML attribute string
listAttribsToString :: ListAttributes -> String
listAttribsToString (startnum, numstyle, _) =
  let numstyle' = camelCaseToHyphenated $ show numstyle
  in  (if startnum /= 1
          then " start=\"" ++ show startnum ++ "\""
          else "") ++
      (if numstyle /= DefaultStyle
          then " style=\"list-style-type: " ++ numstyle' ++ ";\""
          else "")

-- | Convert bullet or ordered list item (list of blocks) to Custom.
listItemToCustom :: WriterOptions -> [Block] -> State WriterState String
listItemToCustom opts items = do
  contents <- blockListToCustom opts items
  useTags <- get >>= return . stUseTags
  if useTags
     then return $ "<li>" ++ contents ++ "</li>"
     else do
       marker <- get >>= return . stListLevel
       return $ marker ++ " " ++ contents

-- | Convert definition list item (label, list of blocks) to Custom.
definitionListItemToCustom :: WriterOptions
                             -> ([Inline],[[Block]]) 
                             -> State WriterState String
definitionListItemToCustom opts (label, items) = do
  labelText <- inlineListToCustom opts label
  contents <- mapM (blockListToCustom opts) items
  useTags <- get >>= return . stUseTags
  if useTags
     then return $ "<dt>" ++ labelText ++ "</dt>\n" ++
           (intercalate "\n" $ map (\d -> "<dd>" ++ d ++ "</dd>") contents)
     else do
       marker <- get >>= return . stListLevel
       return $ marker ++ " " ++ labelText ++ "\n" ++
           (intercalate "\n" $ map (\d -> init marker ++ ": " ++ d) contents)

-- Auxiliary functions for tables:

tableRowToCustom :: WriterOptions
                    -> [String]
                    -> Int
                    -> [[Block]]
                    -> State WriterState String
tableRowToCustom opts alignStrings rownum cols' = do
  let celltype = if rownum == 0 then "th" else "td"
  let rowclass = case rownum of
                      0                  -> "header"
                      x | x `rem` 2 == 1 -> "odd"
                      _                  -> "even"
  cols'' <- sequence $ zipWith 
            (\alignment item -> tableItemToCustom opts celltype alignment item) 
            alignStrings cols'
  return $ "<tr class=\"" ++ rowclass ++ "\">\n" ++ unlines cols'' ++ "</tr>"

alignmentToString :: Alignment -> [Char]
alignmentToString alignment = case alignment of
                                 AlignLeft    -> "left"
                                 AlignRight   -> "right"
                                 AlignCenter  -> "center"
                                 AlignDefault -> "left"

tableItemToCustom :: WriterOptions
                     -> String
                     -> String
                     -> [Block]
                     -> State WriterState String
tableItemToCustom opts celltype align' item = do
  let mkcell x = "<" ++ celltype ++ " align=\"" ++ align' ++ "\">" ++
                    x ++ "</" ++ celltype ++ ">"
  contents <- blockListToCustom opts item
  return $ mkcell contents
-}

-- | Convert list of Pandoc block elements to Custom.
blockListToCustom :: WriterOptions -- ^ Options
                  -> [Block]       -- ^ List of block elements
                  -> IO String
blockListToCustom opts = fmap unlines . mapM (blockToCustom opts)

-- | Convert list of Pandoc inline elements to Custom.
inlineListToCustom :: WriterOptions -> [Inline] -> IO String
inlineListToCustom opts lst = do
  xs <- mapM (inlineToCustom opts) lst
  return $ concat xs

-- | Convert Pandoc inline element to Custom.
inlineToCustom :: WriterOptions -> Inline -> IO String

inlineToCustom _ (Str str) = return "STR"

inlineToCustom _ Space = return " "

inlineToCustom opts (Emph lst) = return "EMPH"

{-

inlineToCustom opts (Strong lst) = do
  contents <- inlineListToCustom opts lst
  return $ "'''" ++ contents ++ "'''"

inlineToCustom opts (Strikeout lst) = do
  contents <- inlineListToCustom opts lst
  return $ "<s>" ++ contents ++ "</s>"

inlineToCustom opts (Superscript lst) = do
  contents <- inlineListToCustom opts lst
  return $ "<sup>" ++ contents ++ "</sup>"

inlineToCustom opts (Subscript lst) = do
  contents <- inlineListToCustom opts lst
  return $ "<sub>" ++ contents ++ "</sub>"

inlineToCustom opts (SmallCaps lst) = inlineListToCustom opts lst

inlineToCustom opts (Quoted SingleQuote lst) = do
  contents <- inlineListToCustom opts lst
  return $ "\8216" ++ contents ++ "\8217"

inlineToCustom opts (Quoted DoubleQuote lst) = do
  contents <- inlineListToCustom opts lst
  return $ "\8220" ++ contents ++ "\8221"

inlineToCustom opts (Cite _  lst) = inlineListToCustom opts lst

inlineToCustom _ (Code _ str) =
  return $ "<tt>" ++ (escapeString str) ++ "</tt>"

inlineToCustom _ (Math _ str) = return $ "<math>" ++ str ++ "</math>"
                                 -- note:  str should NOT be escaped

inlineToCustom _ (RawInline "mediawiki" str) = return str 
inlineToCustom _ (RawInline "html" str) = return str 
inlineToCustom _ (RawInline _ _) = return ""

inlineToCustom _ (LineBreak) = return "<br />\n"


inlineToCustom opts (Link txt (src, _)) = do
  label <- inlineListToCustom opts txt
  case txt of
     [Code _ s] | s == src -> return src
     _  -> if isURI src
              then return $ "[" ++ src ++ " " ++ label ++ "]"
              else return $ "[[" ++ src' ++ "|" ++ label ++ "]]"
                     where src' = case src of
                                     '/':xs -> xs  -- with leading / it's a
                                     _      -> src -- link to a help page
inlineToCustom opts (Image alt (source, tit)) = do
  alt' <- inlineListToCustom opts alt
  let txt = if (null tit)
               then if null alt
                       then ""
                       else "|" ++ alt'
               else "|" ++ tit
  return $ "[[Image:" ++ source ++ txt ++ "]]"

inlineToCustom opts (Note contents) = do 
  contents' <- blockListToCustom opts contents
  modify (\s -> s { stNotes = True })
  return $ "<ref>" ++ contents' ++ "</ref>"
  -- note - may not work for notes with multiple blocks
-}
