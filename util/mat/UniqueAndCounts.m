function [uniqueValues, counts] = UniqueAndCounts(values)
    [uniqueValues, i, descriptionndx] = unique(values);
    counts = hist(descriptionndx, 1:length(uniqueValues));
    counts = counts(:);
    uniqueValues = uniqueValues(:);
end