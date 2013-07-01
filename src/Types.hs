module Types where

import Data.Time (UTCTime)

data RefreshMessage = RefreshNowM | RefreshEachM Int | RefreshTimeM

data SignalFromUI = RefreshEach Int

data SignalToUI =
	Refreshing |
	DoneRefreshing |
	NewHeadline {title::String, link::String, date::UTCTime} |
	Error String
