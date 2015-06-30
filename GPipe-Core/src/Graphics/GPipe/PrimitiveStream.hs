{-# LANGUAGE TypeFamilies, TypeSynonymInstances, FlexibleContexts, FlexibleInstances, ScopedTypeVariables, Arrows, GeneralizedNewtypeDeriving #-}

module Graphics.GPipe.PrimitiveStream where

import Control.Monad.Trans.Class
import Control.Monad.Trans.Writer.Lazy
import Control.Monad.Trans.State.Lazy
import Prelude hiding (length, id, (.))
import Graphics.GPipe.Buffer
import Graphics.GPipe.Expr
import Graphics.GPipe.Shader
import Graphics.GPipe.Compiler
import Graphics.GPipe.PrimitiveArray
import Graphics.GPipe.IndexArray 
import qualified Graphics.GPipe.IndexArray as IndexArray (length)
import Control.Category
import Control.Arrow
import Data.Foldable (forM_)
import Data.Monoid (Monoid(..))
import Data.IntMap.Lazy (insert)
import Foreign.Storable (Storable)

--------------------

--------------------
type DrawCallName = Int
data PrimitiveStreamData = PrimitiveStreamData DrawCallName

newtype PrimitiveStream t a = PrimitiveStream [(a, PrimitiveStreamData)] deriving Monoid

instance Functor (PrimitiveStream t) where
        fmap f (PrimitiveStream xs) = PrimitiveStream $ map (first f) xs

class BufferFormat a => VertexInput a where
    type VertexFormat a
    toVertex :: ToVertex a (VertexFormat a)  

newtype ToVertex a b = ToVertex (Kleisli (StateT Int (Writer [Binding -> IO ()])) a b) deriving (Category, Arrow)

   
                                                              
toPrimitiveStream :: forall os f s a p. (VertexInput a, PrimitiveTopology p) => (s -> PrimitiveArray p a) -> Shader os f s (PrimitiveStream p (VertexFormat a))   
toPrimitiveStream sf = Shader $ do n <- getName
                                   let sampleBuffer = makeBuffer undefined undefined :: Buffer os a
                                       x = fst $ runWriter (evalStateT (mf $ bufBElement sampleBuffer $ BInput 0 0) 0) 
                                   doForInputArray n (map drawcall . getPrimitiveArray . sf)
                                   return $ PrimitiveStream [(x, PrimitiveStreamData n)] 
    where 
        ToVertex (Kleisli mf) = toVertex :: ToVertex a (VertexFormat a)
        drawcall (PrimitiveArraySimple p l a) binds = do runAttribs  a binds
                                                         glDrawArrays (toGLtopology p) 0 l
        drawcall (PrimitiveArrayIndexed p i a) binds = do 
                                                    runAttribs a binds
                                                    bindIndexBuffer i
                                                    glDrawElements (toGLtopology p) (IndexArray.length i) (indexType i) (offset i)
        drawcall (PrimitiveArrayInstanced p il l a) binds = do
                                              runAttribs a binds
                                              glDrawArraysInstanced (toGLtopology p) 0 l il
        drawcall (PrimitiveArrayIndexedInstanced p i il a) binds = do
                                                      runAttribs a binds
                                                      bindIndexBuffer i
                                                      glDrawElementsInstanced (toGLtopology p) (IndexArray.length i) (indexType i) (offset i) il
        bindIndexBuffer i = do forM_ (restart i) glRestartIndex 
                               glBindBuffer (iArrName i) glELEMENT_ARRAY                                                      

        assignIxs :: Int -> Int -> [Int] -> [Int -> IO ()] -> [IO ()]
        assignIxs n ix xxs@(x:xs) (f:fs) | x == n    = f ix : assignIxs (n+1) (ix+1) xs fs
                                         | otherwise = assignIxs (n+1) (ix+1) xxs fs
        assignIxs _ _ _ [] = []                                          
        assignIxs _ _ _ _ = error "Too few attributes generated in toPrimitiveStream"
        
        runAttribs a binds = sequence_ $ assignIxs 0 0 binds $ snd $ runWriter (runStateT (mf a) 0)

        doForInputArray :: Int -> (s -> [[Binding] -> IO()]) -> ShaderM s ()
        doForInputArray n io = modifyRenderIO (\s -> s { inputArrayToRenderIOs = insert n io (inputArrayToRenderIOs s) } )

data InputIndices = InputIndices {
        inputVertexID :: VInt,
        inputInstanceID :: VInt
    }

withInputIndices :: PrimitiveStream p a -> PrimitiveStream p (a, InputIndices)  
withInputIndices = fmap (\a -> (a, InputIndices (scalarS' "gl_VertexID") (scalarS' "gl_InstanceID")) )

makeVertexFx norm n f styp typ b = do 
                             n <- get
                             put $ n + 1
                             lift $ tell [\ix -> glBindBuffer (bName b) glVERTEX_ARRAY  >> glAttribPointer ix n typ norm (bStride b) (bStride b * bSkipElems b + bOffset b)]
                             return (f styp $ useVInput styp n)

makeVertexFnorm n f styp typ (BNormalized b) = makeVertexFx True n f styp typ b 
makeVertexF = makeVertexFx False

makeVertexI n f styp typ b = do 
                             n <- get
                             put $ n + 1
                             lift $ tell [\ix -> glBindBuffer (bName b) glVERTEX_ARRAY  >> glAttribPointerI ix n typ (bStride b) (bStride b * bSkipElems b + bOffset b)]
                             return (f styp $ useVInput styp n) 


instance VertexInput BFloat where
    type VertexFormat BFloat = VFloat
    toVertex = ToVertex $ Kleisli $ makeVertexF 1 (const S) STypeFloat glFLOAT
       
instance VertexInput BInt32Norm where
    type VertexFormat BInt32Norm = VFloat
    toVertex = ToVertex $ Kleisli $ makeVertexFnorm 1 (const S) STypeFloat glINT32 
instance VertexInput BInt16Norm where
    type VertexFormat BInt16Norm = VFloat
    toVertex = ToVertex $ Kleisli $ makeVertexFnorm 1 (const S) STypeFloat glINT16 
instance VertexInput BInt8Norm where
    type VertexFormat BInt8Norm = VFloat
    toVertex = ToVertex $ Kleisli $ makeVertexFnorm 1 (const S) STypeFloat glINT8 

instance VertexInput BWord32Norm where
    type VertexFormat BWord32Norm = VFloat
    toVertex = ToVertex $ Kleisli $ makeVertexFnorm 1 (const S) STypeFloat glUINT32 
instance VertexInput BWord16Norm where
    type VertexFormat BWord16Norm = VFloat
    toVertex = ToVertex $ Kleisli $ makeVertexFnorm 1 (const S) STypeFloat glUINT16 
instance VertexInput BWord8Norm where
    type VertexFormat BWord8Norm = VFloat
    toVertex = ToVertex $ Kleisli $ makeVertexFnorm 1 (const S) STypeFloat glUINT8 
    
instance VertexInput BInt32 where
    type VertexFormat BInt32 = VInt
    toVertex = ToVertex $ Kleisli $ makeVertexI 1 (const S) STypeInt glINT32
instance VertexInput BInt16 where
    type VertexFormat BInt16 = VInt
    toVertex = ToVertex $ Kleisli $ makeVertexI 1 (const S) STypeInt glINT16
instance VertexInput BInt8 where
    type VertexFormat BInt8 = VInt
    toVertex = ToVertex $ Kleisli $ makeVertexI 1 (const S) STypeInt glINT8

instance VertexInput BWord32 where
    type VertexFormat BWord32 = VWord
    toVertex = ToVertex $ Kleisli $ makeVertexI 1 (const S) STypeInt glUINT32
instance VertexInput BWord16 where
    type VertexFormat BWord16 = VWord
    toVertex = ToVertex $ Kleisli $ makeVertexI 1 (const S) STypeInt glUINT16
instance VertexInput BWord8 where
    type VertexFormat BWord8 = VWord
    toVertex = ToVertex $ Kleisli $ makeVertexI 1 (const S) STypeInt glUINT8

-- TODO: B2 B3 B4 instances

                                             
instance (VertexInput a, VertexInput b) => VertexInput (a,b) where
    type VertexFormat (a,b) = (VertexFormat a, VertexFormat b)
    toVertex = proc (a,b) -> do a' <- toVertex -< a
                                b' <- toVertex -< b
                                returnA -< (a', b')

instance (VertexInput a, VertexInput b, VertexInput c) => VertexInput (a,b,c) where
    type VertexFormat (a,b,c) = (VertexFormat a, VertexFormat b, VertexFormat c)
    toVertex = proc (a,b,c) -> do a' <- toVertex -< a
                                  b' <- toVertex -< b
                                  c' <- toVertex -< c
                                  returnA -< (a', b', c')

instance (VertexInput a, VertexInput b, VertexInput c, VertexInput d) => VertexInput (a,b,c,d) where
    type VertexFormat (a,b,c,d) = (VertexFormat a, VertexFormat b, VertexFormat c, VertexFormat d)
    toVertex = proc (a,b,c,d) -> do a' <- toVertex -< a
                                    b' <- toVertex -< b
                                    c' <- toVertex -< c
                                    d' <- toVertex -< d
                                    returnA -< (a', b', c', d')


glDrawArrays :: Int -> Int -> Int -> IO ()
glDrawArrays a b c = putStrLn $ "glDrawArrays " ++ show (a,b,c)

glDrawArraysInstanced :: Int -> Int -> Int -> Int -> IO ()
glDrawArraysInstanced a b c d = putStrLn $ "glDrawArraysInstanced " ++ show (a,b,c,d)

glDrawElements :: Int -> Int -> Int -> Int -> IO ()
glDrawElements a b c d = putStrLn $ "glDrawElements " ++ show (a,b,c,d)

glDrawElementsInstanced :: Int -> Int -> Int -> Int -> Int -> IO ()
glDrawElementsInstanced a b c d e = putStrLn $ "glDrawElementsInstanced " ++ show (a,b,c,d,e)
 
glRestartIndex :: Int -> IO ()
glRestartIndex a = putStrLn $ "glRestartIndex " ++ show a

glBindBuffer :: Int -> Int -> IO ()
glBindBuffer a b = putStrLn $ "glBindBuffer " ++ show (a,b)                                

glAttribPointer :: Int -> Int -> Int -> Bool -> Int -> Int -> IO () 
glAttribPointer a b c d e f = putStrLn $ "glAttribPointer " ++ show (a,b,c,d,e,f)                              
glAttribPointerI :: Int -> Int -> Int -> Int -> Int -> IO () 
glAttribPointerI a b c d e = putStrLn $ "glAttribPointerI " ++ show (a,b,c,d,e)                              

glINT32 = 0 :: Int
glINT16 = 1 :: Int
glINT8 =  2 :: Int
glUINT32 = 3 :: Int
glUINT16 = 4 :: Int
glUINT8 = 5 :: Int
glFLOAT = 6 :: Int

glVERTEX_ARRAY :: Int
glVERTEX_ARRAY = 1

glELEMENT_ARRAY :: Int
glELEMENT_ARRAY = 1
