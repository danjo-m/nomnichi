module Handler.Nomnichi
  ( getNomnichiR       -- ノムニチトップ
  , getCreateArticleR  -- 記事投稿ページの表示
  , postCreateArticleR -- 記事の投稿
  , getArticleR        -- 記事の表示
  , postArticleR       -- 記事の編集
  , getEditArticleR    -- 記事の編集画面の表示
  , postDeleteArticleR -- 記事の削除
  , postCommentR       -- コメントの投稿
  )
where

import Import as I
import Data.Monoid
import Data.Time
import System.Locale (defaultTimeLocale)
import System.IO.Unsafe (unsafePerformIO)

import Yesod.Form.Nic (YesodNic, nicHtmlField)
-- import Data.Attoparsec.Text
import Data.Text as T
import Yesod.Auth
import Data.List as I (lines, unlines, isPrefixOf)
import Text.Blaze.Html (preEscapedToHtml)
import Text.Blaze.Html.Renderer.String (renderHtml)

instance YesodNic App


-- 記事作成，閲覧，更新


-- ノムニチトップ
getNomnichiR :: Handler Html
getNomnichiR = do
  creds <- maybeAuthId
  articles <- case creds of
    Just _ -> runDB $ selectList [] [Desc ArticleId]
    Nothing -> runDB $ selectList [ArticleApproved ==. True] [Desc ArticleId]
  paramPage <- lookupGetParam "page"
  defaultLayout $ do
    $(widgetFile "articles")

convTextToInt :: Text -> Int
convTextToInt text = read $ T.unpack text :: Int

calcNumOfArticles :: Text -> Int
calcNumOfArticles text = (convTextToInt text) * parPage

calcNumOfDroppingArticles :: Text -> Int
calcNumOfDroppingArticles text = (convTextToInt text - 1) * parPage

getCreateArticleR :: Handler Html
getCreateArticleR = do
  (articleWidget, enctype) <- generateFormPost entryForm
  defaultLayout $ do
    $(widgetFile "createArticleForm")

parPage :: Int
parPage = 10

-- 記事作成
postCreateArticleR :: Handler Html
postCreateArticleR = do
  ((res, articleWidget), enctype) <- runFormPost entryForm
  case res of
    FormSuccess article -> do
      articleId <- runDB $ insert article
      setMessage $ toHtml (articleTitle article) <> " created."
      redirect $ ArticleR articleId
    _ -> defaultLayout $ do
      setTitle "Please correct your entry form."
      $(widgetFile "articleAddError")

-- 記事表示
getArticleR :: ArticleId -> Handler Html
getArticleR articleId = do
  creds <- maybeAuthId
  article  <- runDB $ get404 articleId
  comments <- runDB $ selectList [CommentArticleId ==. articleId] [Asc CommentId]
  (commentWidget, enctype) <- generateFormPost $ commentForm articleId
  case creds of
    Just _ ->
      defaultLayout $ do
        setTitle $ toHtml $ articleTitle article
        $(widgetFile "authedArticle")
    Nothing ->
      case articleApproved article of
        True ->
          defaultLayout $ do
            setTitle $ toHtml $ articleTitle article
            $(widgetFile "article")
        False ->
          defaultLayout $ do
          redirect $ NomnichiR

-- 記事更新
postArticleR :: ArticleId -> Handler Html
postArticleR articleId = do
  ((res, articleWidget), enctype) <- runFormPost (editForm Nothing)
  case res of
    FormSuccess article -> do
      runDB $ do
        update articleId
          [ ArticleMemberName =. articleMemberName article
          , ArticleTitle   =. articleTitle   article
          , ArticlePermaLink =. articlePermaLink article
          , ArticleContent =. articleContent article
          , ArticleUpdatedOn =. articleUpdatedOn article
          , ArticlePublishedOn =. articlePublishedOn article
          , ArticleApproved =. articleApproved article
          , ArticlePromoteHeadline =. articlePromoteHeadline  article
          ]
      setMessage $ toHtml $ (articleTitle article) <> " is updated."
      redirect $ ArticleR articleId
    _ -> defaultLayout $ do
      setTitle "Please correct your entry form."
      $(widgetFile "editArticleForm")

-- 編集画面
getEditArticleR :: ArticleId -> Handler Html
getEditArticleR articleId = do
  article <- runDB $ get404 articleId
  (articleWidget, enctype) <- generateFormPost $ editForm (Just article)
  defaultLayout $ do
    $(widgetFile "editArticleForm")


-- 記事削除

postDeleteArticleR :: ArticleId -> Handler Html
postDeleteArticleR articleId = do
  runDB $ do
    delete articleId
    deleteWhere [ CommentArticleId ==. articleId ]
  setMessage "successfully deleted."
  redirect $ NomnichiR


-- コメント



-- コメント送信
postCommentR :: ArticleId -> Handler Html
postCommentR articleId = do
  ((res, commentWidget), enctype) <- runFormPost $ commentForm articleId
  case res of
    FormSuccess comment -> do
      commentId <- runDB $ insert comment
      setMessage "your comment was successfully posted."
      redirect $ ArticleR articleId
    _ -> do
      setMessage "please fill up your comment form."
      redirect $ ArticleR articleId

-- 記事表示時の公開時刻の整形
formatToNomnichiTime :: Article ->  String
formatToNomnichiTime article = formatTime defaultTimeLocale format $ utcToNomnichiTime $ articlePublishedOn article
  where format = "%Y/%m/%d (%a)  %H:%M"
        utcToNomnichiTime = utcToLocalTime $ unsafePerformIO getCurrentTimeZone

-- コメント投稿時刻の整形
formatToCommentTime :: Comment ->  String
formatToCommentTime comment = formatTime defaultTimeLocale format $ utcToNomnichiTime $ commentCreatedAt comment
  where format = "%Y/%m/%d (%a)  %H:%M"
        utcToNomnichiTime = utcToLocalTime $ unsafePerformIO getCurrentTimeZone


-- フォーム
entryForm :: Form Article
entryForm = renderDivs $ Article
  <$> areq textField    "MemberName"   Nothing
  <*> areq textField    "Title"        Nothing
  <*> areq textField    "PermaLink"    Nothing
  <*> areq htmlField "Content"      Nothing
  <*> lift (liftIO getCurrentTime) --
  <*> lift (liftIO getCurrentTime) --
  <*> lift (liftIO getCurrentTime) --
  <*> areq boolField    "Approved" (Just False)
  <*> areq intField     "Count"        Nothing
  <*> areq boolField    "PromoteHeadline" (Just False)

editForm :: Maybe Article -> Form Article
editForm article = renderDivs $ Article
  <$> areq textField    "MemberName" (articleMemberName <$> article)
  <*> areq textField    "Title"    (articleTitle <$> article)
  <*> areq textField    "PermaLink"  (articlePermaLink <$> article)
  <*> areq htmlField "Content"  (articleContent <$> article)
  <*> lift (liftIO getCurrentTime)
  <*> lift (liftIO getCurrentTime)
  <*> lift (liftIO getCurrentTime)
  <*> areq boolField    "Approved" (articleApproved <$> article)
  <*> areq intField     "Count"    (articleCount <$> article)
  <*> areq boolField    "PromoteHeadline" (articlePromoteHeadline <$> article)

commentForm :: ArticleId -> Form Comment
commentForm articleId = renderDivs $ Comment
  <$> areq textField     "Name"    Nothing
  <*> areq textareaField "Comment" Nothing
  <*> lift (liftIO getCurrentTime)
  <*> lift (liftIO getCurrentTime)
  <*> pure articleId

-- ヘッドライン
takeHeadLine :: Html -> Html
takeHeadLine content = preEscapedToHtml $ prettyHeadLine $ renderHtml content

prettyHeadLine :: String -> String
prettyHeadLine article = gsub "_br_" "<br>" $ stripTags $ gsub "<br>" "_br_" $ I.unlines $ foldArticle $ I.lines article

stripTags' bool (x:xs)
  | xs   == []    = if x == '>'
                    then []
                    else [x]
  | bool == True  = if x == '>'
                    then stripTags' False xs
                    else stripTags' True xs
  | bool == False = if x == '<'
                    then stripTags' True xs
                    else x : (stripTags' False xs)
stripTags str = stripTags' False str

gsub _ _ [] = []
gsub x y str@(s:ss)
  | I.isPrefixOf x str = y ++ gsub x y (I.drop (I.length x) str)
  | otherwise = s:gsub x y ss

foldArticle :: [String] -> [String]
foldArticle lines = if lines == headLine
                    then I.take defaultNumOfLines lines
                    else headLine
  where headLine = foldAtFolding lines

foldAtFolding :: [String] -> [String]
foldAtFolding (x:xs)
  | x /= "<!-- folding -->" = if xs == []
                              then [x]
                              else x:foldAtFolding xs
  | x == "<!-- folding -->" = []
  | otherwise = []

defaultNumOfLines :: Int
defaultNumOfLines = 3
