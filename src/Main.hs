module Main (main) where

import Prelude (show)
import BasicPrelude hiding (show)
import Data.Char (toUpper)
import Control.Concurrent (forkIO, threadDelay, Chan, newChan, readChan, writeChan)
import Control.Monad.Trans.State (get, put, runStateT)
import Control.Error (EitherT, hoistEither, fmapLT, throwT, note, eitherT, tryIO)

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
import Text.Feed.Query (getFeedItems, getItemTitle, getItemLink, getItemPublishDate, getItemId)

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

itemToSignal :: UTCTime -> Item -> SignalToUI
itemToSignal now it = NewHeadline {
		title = fromMaybe "" $ getItemTitle it,
		link  = fromMaybe "" $ getItemLink it,
		date = maybe now posixToUTC (approxidate =<< getItemPublishDate it)
	}

-- | Takes a list of item ids not to emit, and return list of item ids emitted
refreshFeed :: (MonadIO m) => [String] -> m [String]
refreshFeed noEmit = liftIO $ done <=< eitherT handleError return $ do
	liftIO $ emit Refreshing
	now <- liftIO getCurrentTime
	items <- (filter ((`notElem` noEmit') . fmap snd . getItemId) . getFeedItems)
		<$> fmapLT show fetchFeed
	mapM_ (emit . itemToSignal now) items
	return (mapMaybe (fmap snd . getItemId) items)
	where
	-- Always emit DoneRefreshing, even on error
	done ids = emit DoneRefreshing >> return ids
	handleError e = emit (Error e) >> return []
	noEmit' = map Just noEmit

refreshServer :: Chan RefreshMessage -> IO ()
refreshServer chan = void $ (`runStateT` (0,[])) $ forever $ do
	msg <- liftIO $ readChan chan
	case msg of
		RefreshNowM -> do
			(t,ids) <- get
			newIds <- refreshFeed ids
			put (t, ids ++ newIds)
		RefreshEachM t -> do
			(oldt,ids) <- get
			put (t,ids)
			liftIO $ when (oldt < 1) (writeChan chan RefreshTimeM)
		RefreshTimeM -> do
			liftIO $ writeChan chan RefreshNowM
			(t,_) <- get
			when (t > 0) $
				liftIO $ void $ forkIO $ do
					threadDelay (t*1000000)
					writeChan chan RefreshTimeM

fromUIThread :: Chan RefreshMessage -> IO ()
fromUIThread refreshChan = forever (popSignalFromUI >>= handleFromUI refreshChan)

handleFromUI :: Chan RefreshMessage -> SignalFromUI -> IO ()
handleFromUI refreshChan (RefreshEach n) = writeChan refreshChan (RefreshEachM n)

main :: IO ()
main = do
	refreshChan <- newChan
	void $ forkIO $ refreshServer refreshChan
	void $ forkIO $ fromUIThread refreshChan
	haskadesRun "asset:///ui.qml"
