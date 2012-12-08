module Types where

import Data.Time (UTCTime)

data RefreshMessage = RefreshNow | RefreshEach Int | RefreshTime

data Slots = Slots {
	refreshEach :: Int -> IO (),
	refresh :: IO ()
}

data Signal =
	Refreshing |
	DoneRefreshing |
	NewHeadline {title::String, link::String, summary::String, date::UTCTime} |
	Error String
