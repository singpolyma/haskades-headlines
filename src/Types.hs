module Types where

import Data.Time (UTCTime)

data Slots = Slots {
	refresh :: IO ()
}

data Signal =
	ResetHeadlines |
	NewHeadline {title::String, link::String, summary::String, date::UTCTime} |
	Error String
