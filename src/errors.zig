pub const MnemeError = error{
    InvalidDimension,
    EmptyVector,
    ZeroVector,
    DuplicateId,
    IdNotFound,
    InvalidMagic,
    UnsupportedVersion,
    InvalidMetric,
    TruncatedFile,
    CorruptRecord,
    VectorLengthMismatch,
};
