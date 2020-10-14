function summarizeSequences(csvFilename, cdsLength, preCDS, childAlignment, parentAlignment)
%{
summarizeSeq.m Finds the most unique sequences in a library of mutant 
sequences and, if provided parentAlignment, finds their potential parents 
from the previous library. Exports results into a .csv file.
Inputs:
    csvFilename     :   string, filename to export results
    cdsLength       :   int, the number of bases in the CDS of interest
    preCDS          :   string, the 10 bases in the vector immediately 
                        before the start of the CDS in all caps
    childAlignment	:   string, '.sam' file with sequence of
                        mutants from the CURRENT round of evolution
                        aligned to the original template
    parentAlignment :   (optional) string, '.sam' file with sequence of
                        mutants from the PREVIOUS round of evolution
                        aligned to the original template
Notes:
    - This program works by matching the protein sequence of the mutant to
    the protein sequence of the reference. It only considers point
    mutations and cannot account for deletions or insertions.
    - For childAlignment and parentAlignment files, export an alignment
    created from the 'align to reference' tool as a '.sam' file.
    - cdsLength = 681 for Rosmarinus
    - preCDS = 'TAAGGATCCG' for Rosmarinus
%}

childAndParent = nargin>4; % Boolean of whether or not parentAlignment was provided

% Analyze childAlignment to find mutations and select mutants
analyzedChild = analyzeAlignment(childAlignment);

if childAndParent
    summaryEndId = 3; % the last id in analyzedSeqs containing summary info
    sampleStartId = 4; % the first id in analyzedSeqs containing sample info
    
    % Analyze parentAlignment to find mutations and select mutants
    analyzedParent = analyzeAlignment(parentAlignment);
    
    % Create field 'Label' to denote Child or Parent library
    [analyzedChild.Label] = deal('Child');
    [analyzedParent.Label] = deal('Parent');
    
    % Create one structure to hold both the child and the parent libraries
    analyzedSeqs = [analyzedChild(2:end), analyzedParent(2:end)];
    
    % Shift the structure by three to place summaries at the beginning
    analyzedSeqs((1:end)+3) = analyzedSeqs;
    
    % Edit 'Label' and 'Select' of summary locations
    analyzedSeqs(1).Label = 'Children and Parents';
    analyzedSeqs(2).Label = 'Children';
    analyzedSeqs(3).Label = 'Parents';
    [analyzedSeqs(1:3).Select] = deal(false);
    
    % Fill in .Mutations for summary locations
    analyzedSeqs(1).Mutations = unique([analyzedChild(1).Mutations, analyzedParent(1).Mutations],'stable');
    analyzedSeqs(2).Mutations = analyzedChild(1).Mutations;
    analyzedSeqs(3).Mutations = analyzedParent(1).Mutations;
else
    analyzedSeqs = analyzedChild;
    summaryEndId = 1; % the last id in analyzedSeqs containing summary info
    sampleStartId = 2; % the first id in analyzedSeqs containing sample info
end

nUniqueMutations = length(analyzedSeqs(1).Mutations);

% Fill fields in analyzedSeqs structure
analyzedSeqs = fillHasMutation(analyzedSeqs);
analyzedSeqs = fillstrAndnMutations(analyzedSeqs);
[analyzedSeqs, key] = fillabcMutations(analyzedSeqs);

% Find parents for children
if childAndParent
    analyzedSeqs = findParents(analyzedSeqs);
end

cellForExport = [createSummaryCell(analyzedSeqs); createSampleCell(analyzedSeqs)];

% Export results to csv file.
cell2csv(cellForExport,csvFilename);


% Helper Functions

    function goodSeqs = findAndTranslateCDS(samfile)
        % Read the '.sam' file into MATLAB, then find the preCDS sequence
        % and if found, store the CDS in 'CDS' field. Also translate the CDS
        % to the 'Protein' field. Only return sequences that contained the
        % preCDS sequence and the full CDS. 
        
        seqs = samread(samfile);
        
        for iSeq = 1:length(seqs)
            cdsLoc = strfind(seqs(iSeq).Sequence,preCDS) + 10;
            if ~isempty(cdsLoc) && length(seqs(iSeq).Sequence(cdsLoc:end)) >= cdsLength 
                seqs(iSeq).CDS = seqs(iSeq).Sequence(cdsLoc:cdsLoc+cdsLength);
            elseif iSeq == 1 % The reference sequence might only contain the CDS and not the vector
                seqs(iSeq).CDS = seqs(iSeq).Sequence;
            end
        end
        % Get the sequences with a full CDS
        goodSeqs = seqs(~cellfun(@isempty,{seqs.CDS}));
        % Translate CDS
        protein = nt2aa({goodSeqs.CDS});
        [goodSeqs.Protein] = protein{:};
        % Create 'Name' field to only contain sample name given to sequencing
        % company
        underscores = strfind({goodSeqs(2:end).QueryName},'_');
        isGenscript = (length(underscores{1}) == 2) || (length(underscores{1}) == 4);
        if isGenscript % Genscript has sample name at the end
            ids = cellfun(@(x) x(end-1)+1:x(end)-1, underscores, 'un', 0);
        else % Eurofins has sample name at the beginning
            ids = cellfun(@(x) 1:x(1)-1, underscores, 'un', 0);
        end
        for i = 2:length(goodSeqs)
            goodSeqs(i).Name = goodSeqs(i).QueryName(ids{i-1});
        end
    end


    function analyzedSeqs = initializeAnalyzedSeqs(goodSeqs)
        % Create a structure with fields corresponding to properties;
        % columns within fields corresponding to samples
        analyzedSeqs = struct(...
            'Name', {goodSeqs.Name},... % sequence name from .sam file
            'Protein',{goodSeqs.Protein},... % the protein sequence translated from the CDS
            'Select',false,... % boolean whether or not it was selected
            'Mutations',[],... % cell containing mutations (e.g. V6A)
            'strMutations',[],... % string of mutations separated by commas
            'abcMutations',[],... % string containing mutations represented by letters of the alphabet
            'nMutations',[],... % int of number of mutations
            'HasMutation',[]); % vector, rows correspond to particular mutations
    end


    function analyzedSeqs = findMutations(analyzedSeqs)
        % Find mutations relative to reference for each sequence:
        for j = 1:length(analyzedSeqs(1).Protein) % Loop through amino acid positions
            for k = 2:length(analyzedSeqs)
                wt = analyzedSeqs(1).Protein(j); % Amino acid of reference at position j
                mt = analyzedSeqs(k).Protein(j); % Amino acid of mutant at position j
                if ~strcmp(mt, wt)
                    mutation = [wt num2str(j+1) mt]; % amino acid number is j+1 to match the pdb file numbering.
                    analyzedSeqs(k).Mutations{end+1} = mutation;
                    % store all mutations in analyzedSeqs(1).Mutations:
                    analyzedSeqs(1).Mutations{end+1} = mutation;
                end
            end
        end
        % Reduce all mutations to the unique mutations
        analyzedSeqs(1).Mutations = unique(analyzedSeqs(1).Mutations,'stable');
    end


    function analyzedSeqs = selectMutants(analyzedSeqs)
        % Selects mutants whose mutations do not fully overlap with other 
        % selected mutants.
        
        % Going from mutants with the most number of mutations to mutants 
        % with the least number of mutations, it checks to see if any of the 
        % selected mutants contains all of the mutations in the current 
        % mutant. If not, the current mutant is selected.
        
        % The structure analyzedSeqs has the reference sequence at index 1.
        nMutants = length(analyzedSeqs)-1;
        
        % Initialize a matrix with row 1 as index of mutant, row 2 as zeros
        mutationCounts = [2:length(analyzedSeqs);zeros(1,nMutants)];
        
        % Fill in row 2 with the number of mutations for that mutant
        for m = 1:nMutants
            mutationCounts(2,m) = length(analyzedSeqs(m+1).Mutations);
        end
        
        % Sort mutationCounts by the number of mutations
        mutationCounts = mutationCounts';
        mutationCounts = sortrows(mutationCounts,2,'descend');
        
        % Loop through mutants, starting from the one with the most number of mutations
        for n = 1:nMutants 
            % Index of mutant in analyzedSeqs
            iMutant = mutationCounts(n,1);
            % Indices of already selected mutants
            selected = find([analyzedSeqs(:).Select]);
            % Check the current mutant's mutations against other already
            % selected mutants
            mutantMutations = analyzedSeqs(iMutant).Mutations;
            analyzedSeqs(iMutant).Select = true; % initialize
            for iSelect = selected
                selectMutations = analyzedSeqs(iSelect).Mutations;
                allMutations = [mutantMutations selectMutations];
                uniqueMutations = unique(allMutations);
                % if any iSelect contains all the mutations present
                % in iMutant, then iMutant will not be selected.
                if length(uniqueMutations) == length(selectMutations)
                    analyzedSeqs(iMutant).Select = false;
                    break
                end
            end
        end
    end


    function analyzedSeqs = analyzeAlignment(samfile)
        % Performs all of the steps to select unique mutants from a .sam
        % alignment file from Snapgene's 'Align to Reference' tool.
        % Inputs:
        %    samfile :   string, filename of '.sam' alignment file
        goodSeqs = findAndTranslateCDS(samfile);
        analyzedSeqs = initializeAnalyzedSeqs(goodSeqs);
        analyzedSeqs = findMutations(analyzedSeqs);
        analyzedSeqs = selectMutants(analyzedSeqs);
    end


    function analyzedSeqs = fillstrAndnMutations(analyzedSeqs)
        for i = 1:length(analyzedSeqs)
            analyzedSeqs(i).nMutations = length(analyzedSeqs(i).Mutations);
            analyzedSeqs(i).strMutations = strjoin(analyzedSeqs(i).Mutations, ',');
        end
    end


    function [analyzedSeqs, key] = fillabcMutations(analyzedSeqs)
        % Create mutation to letter key based on all unique mutations
        % The key has three columns, column 1 is the mutation (e.g. 'V7A'), column 2
        % is the corresponding letter (e.g. 'a'), and column 3 is the combined key
        % (e.g. 'V7A (a)')
        
        alphabet = 'abcdefghijklmnopqrstuvwxyz';

        % Create the key
        key = cell(nUniqueMutations,3);
        for iMutation = 1:nUniqueMutations
            key{iMutation,1} = analyzedSeqs(1).Mutations{iMutation};
            if mod(iMutation,26) ~= 0
                key{iMutation,2} = alphabet(mod(iMutation,26));
            else
                key{iMutation,2} = alphabet(26);
            end
            key{iMutation,3} = [key{iMutation,1} ' (' key{iMutation,2} ')'];
        end
        
        % Fill in abcMutations field based on the key
        for iMutant = 1:length(analyzedSeqs)
            for iMutation = 1:length(analyzedSeqs(iMutant).Mutations)
                mutation = analyzedSeqs(iMutant).Mutations{iMutation};
                keyId = find(contains(key(:,1),mutation));
                if childAndParent
                    notInChild = ~any(strcmp(analyzedSeqs(2).Mutations,mutation));
                    notInParent = ~any(strcmp(analyzedSeqs(3).Mutations,mutation));
                    if notInChild || notInParent % Capitalize mutations that are unique to the child or parent library
                        key{keyId,2} = upper(key{keyId,2});
                    end
                end
                analyzedSeqs(iMutant).abcMutations = [analyzedSeqs(iMutant).abcMutations key{keyId,2}];
            end
        end
        key(:,3) = strcat(key(:,1), {' ('}, key(:,2), {')'});
    end


    function analyzedSeqs = findParents(analyzedSeqs)
        
        % Create mutation arrays to find the parents of each child;
        % only the selected mutants in the parent library are considered
        childMutationArray = createMutationArray(analyzedSeqs,'Child');
        parentMutationArray = createMutationArray(analyzedSeqs,'Parent');
        
        % Find parents for each child and store them in column 5 of
        % childMutationArray
        
        % First find parents for the children in which no shuffling occurred, only
        % new mutations.
        for iChild = 1:length(childMutationArray)
            for iParent = 1:length(parentMutationArray)
                if isequal(childMutationArray(iChild,3),parentMutationArray(iParent,3))
                    childMutationArray{iChild,5} = parentMutationArray{iParent,1};
                    break
                end
            end
        end
        
        % Then find parents for the children that were a result of gene shuffling
        children = 1:length(childMutationArray); % indices of all children
        parentless = cellfun(@isempty,childMutationArray(:,5)); % logical to index parentless children
        parents = 1:length(parentMutationArray); % indices of all potential parents
        fullPotential = true(length(parentMutationArray),1); % logical to index all parents
        
        for iChild = children(parentless)
            nChildMutations = length(childMutationArray{iChild,3});
            % initialize potentialParents and hasMutation for each child
            potentialParents = fullPotential;
            hasMutation = fullPotential;
            for iChildMutation = 1:nChildMutations
                childMutation = childMutationArray{iChild,3}{iChildMutation};
                for iPotentialParent = parents(potentialParents)
                    % If the childMutation is not present in iPotentialParent, set
                    % hasMutation at iPotentialParent to be false.
                    if ~any(contains(parentMutationArray{iPotentialParent,3},childMutation))
                        hasMutation(iPotentialParent) = false;
                    end
                end
                
                % if no parents on the potentialParents list had
                % that mutation, then store the potentialParents list as found
                % potential parents for iChild, and find the next potential
                % parents by checking that mutation again with all the parents.
                if ~any(potentialParents & hasMutation)
                    foundParents = parents(potentialParents);
                    childMutationArray{iChild,5}{end+1} = strjoin(parentMutationArray(foundParents,1)','/');
                    potentialParents = fullPotential;
                    hasMutation = fullPotential;
                    % Go through full potential list of parents looking at the same
                    % child mutation to get the second list of potential parents.
                    for iPotentialParent = parents(potentialParents)
                        if ~any(contains(parentMutationArray{iPotentialParent,3},childMutation))
                            hasMutation(iPotentialParent) = false;
                        end
                    end
                end
                % Keep potential parents that had the mutation
                potentialParents = potentialParents & hasMutation;
                % If this is the last mutation then add the potentialParents list as
                % parents
                if iChildMutation == nChildMutations
                    foundParents = parents(potentialParents);
                    childMutationArray{iChild,5}{end+1} = strjoin(parentMutationArray(foundParents,1)','/');
                end
            end
            childMutationArray{iChild,5} = strjoin(childMutationArray{iChild,5},'; ');
        end
        
        % Store parents in new 'Parents' field in analyzedSeqs
        [analyzedSeqs(strcmp({analyzedSeqs.Label}, 'Child')).Parents] = childMutationArray{:,5};
    end


    function mutationArray = createMutationArray(analyzedSeqs, label)
        % Create a cell array size nMutants x 5. 
        % Col 1: Query Name
        % Col 2: Cell with all mutations
        % Col 3: Cell with the mutations common between parent/child libs
        % Col 4: Cell with the mutations unique to the parent/child libs
        % Col 5: Left blank to fill in later (with parents for child array)
        labelIds = find(strcmp({analyzedSeqs.Label}, label));
        length_ = length(labelIds);
        mutationArray = cell(length_,5);
        isChild = strcmp(label, 'Child');
        isParent = ~isChild;
        for n = 1:length_
            id = labelIds(n);
            if (isParent && analyzedSeqs(id).Select) || isChild
                commonid = isstrprop(analyzedSeqs(id).abcMutations,'lower');
                uniqueid = isstrprop(analyzedSeqs(id).abcMutations,'upper');
                mutationArray{n,1} = analyzedSeqs(id).Name;
                mutationArray{n,2} = analyzedSeqs(id).Mutations;
                mutationArray{n,3} = analyzedSeqs(id).Mutations(commonid);
                mutationArray{n,4} = analyzedSeqs(id).Mutations(uniqueid);
            end
        end
        if isParent % keep only full cells (selected parents)
            fullCells = ~cellfun(@isempty,mutationArray(:,1));
            mutationArray = mutationArray(fullCells,:);
        end
    end


    function analyzedSeqs = fillHasMutation(analyzedSeqs)
        % Fill field HasMutation for each mutant, which is a vector the
        % length of the number of mutations present in the library. At each
        % index corresponding to a particular mutation, there is a 1 or a 0
        % to indicate if the mutant has that particular mutation
        [analyzedSeqs.HasMutation] = deal(zeros(nUniqueMutations,1));
        for iMutant = sampleStartId:length(analyzedSeqs)
            for iMutation = 1:nUniqueMutations
                if any(strcmp(analyzedSeqs(iMutant).Mutations,analyzedSeqs(1).Mutations{iMutation}))
                    analyzedSeqs(iMutant).HasMutation(iMutation) = 1;
                end
            end
        end
        % Fill HasMutation for the summary location(s), as a cell containing
        % two vectors. The first vector corresponds to selected mutants and
        % the second vector corresponds to all mutants.
        for iSummary = 1:sampleStartId-1
            analyzedSeqs(iSummary).HasMutation = cell(2,1);
        end
        selected = [analyzedSeqs.Select];
        analyzedSeqs(1).HasMutation{1} = sum([analyzedSeqs(selected).HasMutation],2);
        analyzedSeqs(1).HasMutation{2} = sum([analyzedSeqs(sampleStartId:end).HasMutation],2);
        if childAndParent
            areChildren = strcmp({analyzedSeqs.Label},'Child');
            areParents = strcmp({analyzedSeqs.Label},'Parent');
            analyzedSeqs(2).HasMutation{1} = sum([analyzedSeqs(areChildren&selected).HasMutation],2);
            analyzedSeqs(3).HasMutation{1} = sum([analyzedSeqs(areParents&selected).HasMutation],2);
            analyzedSeqs(2).HasMutation{2} = sum([analyzedSeqs(areChildren).HasMutation],2);
            analyzedSeqs(3).HasMutation{2} = sum([analyzedSeqs(areParents).HasMutation],2);
        end
    end


    function sampleCell = createSampleCell(analyzedSeqs)
        % Create a cell to hold the sample data for csv export (does not
        % include column titles or summary data)
        % Converts everything to strings
        samples = analyzedSeqs(sampleStartId:end);
        % Initialize cell to contain HasMutation vectors; rows are samples,
        % columns are mutations
        hasMutationCell = cell(length(analyzedSeqs) - sampleStartId, nUniqueMutations);
        for i = 1:length(samples)
            hasMutationCell(i,:) = cellfun(@num2str,num2cell(samples(i).HasMutation(:)'),'un',false);
        end
        % Replace any zeroes with blank space '', for hasMutations and
        % select
        hasMutationCell(cell2mat(cellfun(@(elem) elem=='0', hasMutationCell, 'un', false))) = {''};
        selectCell = cellfun(@num2str,{samples.Select},'un',false);
        selectCell(cell2mat(cellfun(@(elem) elem=='0', selectCell, 'un', false))) = {''};
        sampleCell = [[{samples.Name};...
            selectCell;...
            cellfun(@num2str,{samples.nMutations},'un',false);...
            {samples.abcMutations};...
            {samples.strMutations}]', hasMutationCell];
        if childAndParent % Insert 'Label' and 'Parent' as columns after 'Name'
            sampleCell = [sampleCell(:,1), [{samples.Label}; {samples.Parents}]',sampleCell(:,2:end)];
        end
    end


    function summaryCell = createSummaryCell(analyzedSeqs)
        % Create a cell to hold the summary data for csv export
        % (includes titles)
        % Converts everything to strings
        if childAndParent
            children = analyzedSeqs(strcmp({analyzedSeqs.Label}, 'Child'));
            parents = analyzedSeqs(strcmp({analyzedSeqs.Label}, 'Parent'));
        end

        % Create counts vector containing mutant counts for each category
        counts = zeros(summaryEndId*2,1);
        countMutants = @(a) [sum([a.Select]); length(a)]; % function returning counts of selected and all
        counts(1:2) = countMutants(analyzedSeqs(summaryEndId+1:end));
        if childAndParent
            counts(3:4) = countMutants(children);
            counts(5:6) = countMutants(parents);
        end
        
        % Create cell for hasMutation vectors; odd rows represent selected
        % mutants, even rows represent all mutants; will contain the number
        % of mutants with corresponding mutation in each category
        hasMutationCell = cell(summaryEndId * 2, nUniqueMutations);
        % Create cell that will contain the fraction of mutants with
        % corresponding mutation in each category
        fractionCell = hasMutationCell;
        shortnum2str = @(x) num2str(x,'%.2f'); % num2str function which outputs 2 numbers after the decimal point
        
        % Fill hasMutationCell and fractionCell
        j = 1; % index where info is stored in analyzedSeqs
        for i = 1:summaryEndId*2
            if mod(i,2) == 1 % odd; log select
                id = 1;
            else % even; log all
                id = 2;
            end
            hasMutationCell(i,:) = cellfun(@num2str,num2cell(...
                analyzedSeqs(j).HasMutation{id}(:)'),'un',false);
            fractionCell(i,:) = cellfun(shortnum2str,num2cell(...
                analyzedSeqs(j).HasMutation{id}(:)/counts(i)'),'un',false);
            j = j + ~mod(i,2); % increment j when i is even
        end
        % Combine both cells as one
        hasMutationFractionCell = strcat(hasMutationCell, {' ('}, fractionCell, {')'});
        % Replace zeroes with blank space
        hasMutationFractionCell(cell2mat(cellfun(@(elem) elem(1)=='0', hasMutationFractionCell, 'un', false))) = {''};
               
        % Fill other cells to create summaryCell
        titleCell = [{'Name', 'Count/Selected', 'Mutation Count',...
            'Alphabet Mutations', 'Mutations'}, key(:,3)']; % first row
        namesCell = repmat({'Selected';'All'},[summaryEndId,1]); % column
        countsCell = cellfun(@num2str, num2cell(counts),'un',false);% column
        nMutationsCell = repelem(cellfun(@num2str,{analyzedSeqs(1:summaryEndId).nMutations},'un',false),2)'; % column
        abcMutationsCell = repelem({analyzedSeqs(1:summaryEndId).abcMutations},2)'; % column
        strMutationsCell = repelem({analyzedSeqs(1:summaryEndId).strMutations},2)'; % column
        
        % Create final summaryCell by combining everything
        summaryCell = [titleCell; namesCell, countsCell, nMutationsCell, ...
            abcMutationsCell, strMutationsCell, hasMutationFractionCell];
        if childAndParent
            labelCell = [{'Label'}; repelem({analyzedSeqs(1:summaryEndId).Label}',2)];
            parentsCell = [{'Parents'}; cell(6,1)]; % placeholder for Parents
            summaryCell = [summaryCell(:,1), labelCell, parentsCell, summaryCell(:,2:end)];
        end
    end


    function cell2csv(cellArray,csvFilename)
        % Writes a cell array to a csv file.
        
        %Check that .csv is appended to filename
        if ~strcmp(csvFilename(end-3:end),'.csv')
            fid = fopen([csvFilename '.csv'],'wt');
        else
            fid = fopen(csvFilename,'wt');
        end
        
        %Loop through each row of the cell array:
        for i = 1:size(cellArray,1)
            %Write each element of the row with a comma between them
            fprintf(fid,'"%s",', cellArray{i,1:end-1});
            %For the last element in the row, add a new line instead of a comma
            fprintf(fid,'"%s"\n', cellArray{i,end});
        end
        
        fclose(fid);
        
    end


end
