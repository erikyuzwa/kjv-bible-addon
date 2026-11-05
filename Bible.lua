-- Registry for the full KJV text. Each file in Bible\ calls ns.AddBook().
-- Text: King James Version (public domain), via scrollmapper/bible_databases.
local _, ns = ...

ns.Books = {}

function ns.AddBook(name, chapters)
    ns.Books[#ns.Books + 1] = {
        name     = name,
        key      = (name:lower():gsub("%s", "")),
        chapters = chapters,   -- chapters[c][v] = verse text
    }
end
