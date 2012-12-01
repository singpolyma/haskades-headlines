module Main (main) where

import Prelude (show)
import BasicPrelude hiding (show)
import Data.Char (toUpper)
import Control.Concurrent (forkIO)
import Control.Error

import Codec.Text.IConv (EncodingName, convertFuzzy, Fuzzy(Transliterate))
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TL
import qualified Data.Text.Encoding.Error as T
import qualified Data.ByteString.Lazy as LZ

import Network.URI (URI(..), URIAuth(..))
import qualified Network.HTTP as HTTP
import qualified Network.Stream as HTTP (ConnError(..))

import Data.Time.Git (approxidate, posixToUTC)
import Data.Time (UTCTime, getCurrentTime)
import Text.Feed.Types (Feed, Item(..))
import Text.Feed.Import (parseFeedString)
import Text.Feed.Query (getFeedItems, getItemTitle, getItemLink, getItemPublishDate)
import qualified Text.Atom.Feed as Atom

import Types
import HaskadesBinding

feed :: URI
feed = URI "http:" (Just $ URIAuth "" "rss.cbc.ca" "") "/lineup/topstories.xml" "" ""

fetch :: URI -> EitherT HTTP.ConnError IO ByteString
fetch uri = do
	response <- hoistEither =<< fmapLT (HTTP.ErrorMisc . show) (tryIO $
		HTTP.simpleHTTP $ HTTP.mkRequest HTTP.GET uri)
	case HTTP.rspCode response of
		(2,0,0) -> return (HTTP.rspBody response)
		(3,_,_) -> throwT (HTTP.ErrorMisc $ "Redirects not implemented yet: " ++ show response)
		_       -> throwT (HTTP.ErrorMisc $ "HTTP fetch failed with: " ++ show response)

textFromByteString :: EncodingName -> ByteString -> LText
textFromByteString enc bs = case map toUpper enc of
	"UTF-8"    -> TL.decodeUtf8With T.lenientDecode lz
	"UTF-16LE" -> TL.decodeUtf16LEWith T.lenientDecode lz
	"UTF-16BE" -> TL.decodeUtf16BEWith T.lenientDecode lz
	"UTF-32LE" -> TL.decodeUtf32LEWith T.lenientDecode lz
	"UTF-32BE" -> TL.decodeUtf32BEWith T.lenientDecode lz
	_          -> TL.decodeUtf32BEWith T.lenientDecode $
		convertFuzzy Transliterate enc "UTF-32BE" lz
	where
	lz = LZ.fromChunks [bs]

fetchFeed :: EitherT HTTP.ConnError IO Feed
fetchFeed = textFromByteString "UTF-8" <$> fetch feed >>=
	hoistEither . note (HTTP.ErrorMisc "Feed parse failed") .
	parseFeedString . TL.unpack

getTextSummary :: Item -> Maybe String
getTextSummary (AtomItem (Atom.Entry {
		Atom.entrySummary = Just (Atom.TextString s)
	})) = Just s
getTextSummary (AtomItem (Atom.Entry {
		Atom.entryContent = Just (Atom.TextContent s)
	})) = Just s
getTextSummary _ = Nothing -- TODO: Strip HTML?

itemToSignal :: UTCTime -> Item -> Signal
itemToSignal now it = NewHeadline {
		title = fromMaybe "" $ getItemTitle it,
		link  = fromMaybe "" $ getItemLink it,
		summary = fromMaybe "" $ getTextSummary it,
		date = maybe now posixToUTC (approxidate =<< getItemPublishDate it)
	}

refreshFeed :: IO ()
refreshFeed = do
	emit ResetHeadlines
	now <- getCurrentTime
	void $ forkIO $ eitherT (emit . Error) return $
		(map (itemToSignal now) . getFeedItems) <$> fmapLT show fetchFeed >>=
		mapM_ emit

main :: IO ()
main = haskadesRun "asset:///ui.qml" Slots {
	refresh = refreshFeed
}
