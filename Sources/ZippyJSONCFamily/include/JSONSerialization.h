//Copyright (c) 2018 Michael Eisel. All rights reserved.

#import <Foundation/Foundation.h>

CF_EXTERN_C_BEGIN

typedef CF_ENUM(size_t, JNTDecodingErrorType) {
    JNTDecodingErrorTypeNone,
    JNTDecodingErrorTypeKeyDoesNotExist,
    JNTDecodingErrorTypeValueDoesNotExist,
    JNTDecodingErrorTypeNumberDoesNotFit,
    JNTDecodingErrorTypeWrongType,
    JNTDecodingErrorTypeJSONParsingFailed,
};

static const NSInteger kJNTDecoderSize = 25;

#ifdef __cplusplus
struct JNTContext;
typedef JNTContext *ContextPointer;
#else
struct ContextDummy {
};
typedef struct ContextDummy *ContextPointer;
#endif

struct JNTElementStorage {
    void *doc;
    size_t offset;
};

struct JNTContext;

struct JNTDecoderStorage {
    struct JNTElementStorage storage;
    struct JNTContext *context;
};

#ifdef __cplusplus
struct JNTDecoder;
typedef simdjson::dom::array::iterator JNTIterator;
#else
typedef struct JNTDecoderStorage JNTDecoder;
typedef struct JNTElementStorage JNTIterator;
#endif

//typedef JNTDecoder Decoder;
typedef JNTDecoder *DecoderPointer;

JNTDecoder JNTDecoderFromIterator(JNTIterator *iterator, JNTDecoder root);
JNTIterator JNTDocumentGetIterator(JNTDecoder decoder);
bool JNTDocumentIsEmpty(DecoderPointer decoder);
void JNTClearError(ContextPointer context);
ContextPointer JNTGetContext(JNTDecoder decoder);
bool JNTDocumentErrorDidOccur(JNTDecoder decoder);
bool JNTDocumentValueIsInteger(JNTDecoder decoder);
bool JNTDocumentValueIsDouble(JNTDecoder decoder);
bool JNTHasVectorExtensions();
ContextPointer JNTCreateContext(const char *originalString, uint32_t originalStringLength, const char *negInfString, const char *posInfString, const char *nanString);
JNTDecoder JNTDocumentFromJSON(ContextPointer context, const void *data, NSInteger length, bool convertCase, const char * *retryReason, bool *success);
bool JNTDocumentContains(JNTDecoder iterator, const char *key);
void JNTProcessError(ContextPointer context, void (^block)(const char *description, JNTDecodingErrorType type, JNTDecoder value, const char *key));
bool JNTErrorDidOccur(ContextPointer context);
JNTDecoder JNTDocumentFetchValue(JNTDecoder decoder, const char *key);
bool JNTDocumentDecodeNil(JNTDecoder documentPtr);
void JNTReleaseContext(ContextPointer context);
void JNTUpdateFloatingPointStrings(const char *posInfString, const char *negInfString, const char *nanString);
bool JNTDocumentValueIsArray(JNTDecoder iterator);
bool JNTDocumentValueIsDictionary(JNTDecoder iterator);
NSArray <NSString *> *JNTDocumentAllKeys(JNTDecoder decoder);
NSArray <id> *JNTDocumentCodingPath(JNTDecoder iterator);
void JNTDocumentForAllKeyValuePairs(JNTDecoder iterator, void (^callback)(const char *key, JNTDecoder iterator));
void JNTConvertSnakeToCamel(JNTDecoder iterator);
void JNTAdvanceIterator(JNTIterator *iterator, JNTDecoder root);

double JNTDocumentDecode__Double(JNTDecoder value);
float JNTDocumentDecode__Float(JNTDecoder value);
NSDate *JNTDocumentDecode__Date(JNTDecoder value);
void *JNTDocumentDecode__Data(JNTDecoder value, int32_t *outLength);
void JNTRunTests();
bool JNTDocumentValueIsNumber(JNTDecoder value);
const char *JNTDocumentDecode__DecimalString(JNTDecoder value, int32_t *outLength);
// void JNTReleaseValue(DecoderPointer decoder);
JNTDecoder JNTDocumentCreateCopy(JNTDecoder decoder);

NSInteger JNTDocumentGetArrayCount(JNTDecoder value);

@interface JNTCodingPath : NSObject

- (instancetype)initWithStringValue:(NSString *)stringValue intValue:(NSInteger)intValue;

@property (strong, nonatomic) NSString *stringValue;
@property (nonatomic) NSInteger intValue;

@end

#define DECODE_KEYED_HEADER(A, B) DECODE_KEYED_HEADER_NAMED(A, B, A)

#define DECODE_KEYED_HEADER_NAMED(A, B, C) \
A JNTDocumentDecodeKeyed__##C(JNTDecoder value, const char *key);

#define DECODE_HEADER(A, B) DECODE_HEADER_NAMED(A, B, A)

#define DECODE_HEADER_NAMED(A, B, C) \
A JNTDocumentDecode__##C(JNTDecoder value);

#define DECODE_ITER_HEADER(A, B) DECODE_ITER_HEADER_NAMED(A, B, A)

#define DECODE_ITER_HEADER_NAMED(A, B, C) \
A JNTDocumentDecodeIter__##C(JNTDecoder value, JNTIterator iterator);

#define ENUMERATE(F) \
F(int8_t, int64_t); \
F(uint8_t, int64_t); \
F(int16_t, int64_t); \
F(uint16_t, int64_t); \
F(int32_t, int64_t); \
F(uint32_t, int64_t); \
F(int64_t, int64_t); \
F(uint64_t, uint64_t); \
F##_NAMED(bool, bool, Bool); \
F##_NAMED(const char *, const char *, String); \
F##_NAMED(NSInteger, int64_t, Int); \
F##_NAMED(NSUInteger, uint64_t, UInt); \
F##_NAMED(double, double, Double); \
F##_NAMED(float, double, Float);

ENUMERATE(DECODE_HEADER);
ENUMERATE(DECODE_ITER_HEADER);

CF_EXTERN_C_END
