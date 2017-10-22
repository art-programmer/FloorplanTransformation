function [uniqueValues, counts] = SortedUniqueAndCounts(values)
    [uniqueValues, counts] = UniqueAndCounts(values);
    [counts, ind] = sort(counts);
    uniqueValues = uniqueValues(ind);
end