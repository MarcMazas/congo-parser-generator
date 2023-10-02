[#-- This template contains the core logic for generating the various parser routines. --]

[#import "CommonUtils.inc.ftl" as CU]

[#var nodeNumbering = 0]
[#var NODE_USES_PARSER = settings.nodeUsesParser]
[#var NODE_PREFIX = grammar.nodePrefix]
[#var currentProduction]
[#var topLevelExpansion] [#-- A "one-shot" indication that we are processing 
                              an expansion immediately below the BNF production expansion, 
                              ignoring an ExpansionSequence that might be there. This is
                              primarily, if not exclusively, for allowing JTB-compatible
                              syntactic trees to be built. While seemingly silly (and perhaps could be done differently), 
                              it is also a bit tricky, so treat it like the Holy Hand-grenade in that respect. 
                          --]
[#var jtbNameMap = {
   "Terminal" : "nodeToken",
   "Sequence" : "nodeSequence",
   "Choice" : "nodeChoice",
   "ZeroOrOne" : "nodeOptional",
   "ZeroOrMore" : "nodeListOptional",
   "OneOrMore" : "nodeList" }]
[#var nodeFieldOrdinal = {}]
[#var syntheticNodesEnabled = settings.syntheticNodesEnabled && settings.treeBuildingEnabled]
[#var jtbParseTree = syntheticNodesEnabled && settings.jtbParseTree]

[#macro Productions]
// ===================================================================
// Start of methods for BNF Productions
// This code is generated by the ParserProductions.inc.ftl template.
// ===================================================================
[#list grammar.parserProductions as production]
      [#set nodeNumbering = 0]
  [@CU.firstSetVar production.expansion/]
   [#if !production.onlyForLookahead]
    [#set currentProduction = production]
    [@ParserProduction production/]
   [/#if]
[/#list]
[#if settings.faultTolerant]
  [@BuildRecoverRoutines /]
[/#if]
[/#macro]

[#macro ParserProduction production]
    [#set nodeNumbering = 0]
    [#set nodeFieldOrdinal = {}]
    [#set newVarIndex = 0 in CU]
    [#-- Generate the method modifiers and header --] 
        ${production.leadingComments}
        // ${production.location}
        ${globals.startProduction()}${globals.translateModifiers(production.accessModifier)} ${globals.translateType(production.returnType)} Parse${production.name}([#if production.parameterList?has_content]${globals.translateParameters(production.parameterList)}[/#if]) {
            var prevProduction = _currentlyParsedProduction;
            _currentlyParsedProduction = "${production.name}";
            [#--${production.javaCode!}
            This is actually inserted further down because
            we want the prologue java code block to be able to refer to 
            CURRENT_NODE.
            --]
            [#set topLevelExpansion = false]
            ${BuildCode(production)}
        }
        // end of Parse${production.name}${globals.endProduction()}

[/#macro]

[#--
   Macro to build routines that scan up to the start of an expansion
   as part of a recovery routine
--]
[#macro BuildRecoverRoutines]
   [#list grammar.expansionsNeedingRecoverMethod as expansion]
    def ${expansion.recoverMethodName}(self):
        Token initialToken = LastConsumedToken;
        IList<Token> skippedTokens = new List<Token>();
        bool success = false;
        while (LastConsumedToken.Type != TokenType.EOF) {
[#if expansion.simpleName = "OneOrMore" || expansion.simpleName = "ZeroOrMore"]
            if (${ExpansionCondition(expansion.nestedExpansion)}) {
[#else]
            if (${ExpansionCondition(expansion)}) {
[/#if]
                success = true;
                break;
            }
            [#if expansion.simpleName = "ZeroOrMore" || expansion.simpleName = "OneOrMore"]
               [#var followingExpansion = expansion.followingExpansion]
               [#list 1..1000000 as unused]
                [#if followingExpansion?is_null][#break][/#if]
                [#if followingExpansion.maximumSize >0]
                 [#if followingExpansion.simpleName = "OneOrMore" || followingExpansion.simpleName = "ZeroOrOne" || followingExpansion.simpleName = "ZeroOrMore"]
                if (${ExpansionCondition(followingExpansion.nestedExpansion)}):
                 [#else]
                if (${ExpansionCondition(followingExpansion)}):
                 [/#if]
                    success = true;
                    break;
                }
                [/#if]
                [#if !followingExpansion.possiblyEmpty][#break][/#if]
                [#if followingExpansion.followingExpansion?is_null]
                if (OuterFollowSet != null) {
                    if (OuterFollowSet.Contains(NextTokenType)) {
                        success = true;
                        break;
                    }
                }
                 [#break/]
                [/#if]
                [#set followingExpansion = followingExpansion.followingExpansion]
               [/#list]
             [/#if]
            LastConsumedToken = NextToken(LastConsumedToken);
            skippedTokens.AddLastConsumedToken);
        if (!success && skippedTokens.Count > 0) {
             LastConsumedToken = initialToken;
        }
        if (success && skippedTokens.Count > 0) {
            iv = InvalidNode(self);
            [#-- OMITTED: iv.copyLocationInfo(skippedTokens.get(0));--]
            foreach (var tok in skippedTokens) {
                iv.AddChild(tok);
                [#-- OMITTED: iv.setEndOffset(tok.getEndOffset()); --]
            }
            PushNode(iv);
        pendingRecovery = !success;

   [/#list]
[/#macro]

[#macro BuildCode expansion]
[#-- // DBG > BuildCode ${expansion.simpleName} --]
  [#if expansion.simpleName != "ExpansionSequence" && expansion.simpleName != "ExpansionWithParentheses"]
// Code for ${expansion.simpleName} specified at ${expansion.location}
  [/#if]
     [@CU.HandleLexicalStateChange expansion false]
      [#if settings.faultTolerant && expansion.requiresRecoverMethod && !expansion.possiblyEmpty]
if (_pendingRecovery) {
    ${expansion.recoverMethodName}();
}
      [/#if]
       [@BuildExpansionCode expansion/]
     [/@CU.HandleLexicalStateChange]
[#-- // DBG < BuildCode ${expansion.simpleName} --]
[/#macro]

[#macro TreeBuildingAndRecovery expansion]
    [#var production,
          treeNodeBehavior,
          buildingTreeNode=false,
          nodeVarName,
          javaCodePrologue = null,
          parseExceptionVar = CU.newVarName("parseException"),
          callStackSizeVar = CU.newVarName("callStackSize"),
          canRecover = settings.faultTolerant && expansion.tolerantParsing && expansion.simpleName != "Terminal"
    ]
    [#set treeNodeBehavior = resolveTreeNodeBehavior(expansion)]
   [#-- // DBG <> treeNodeBehavior = ${(treeNodeBehavior??)?string!} for expansion ${expansion.simpleName} --]
    [#if expansion == currentProduction]
      [#-- Set this expansion as the current production and capture any Java code specified before the first expansion unit --]
      [#set production = currentProduction]
      [#set javaCodePrologue = production.javaCode!] 
    [/#if]
    [#if treeNodeBehavior??]
        [#if settings.treeBuildingEnabled]
            [#set buildingTreeNode = true]
            [#set nodeVarName = nodeVar(production??)]
        [/#if]
    [/#if]
    [#if !buildingTreeNode && !canRecover]
${globals.translateCodeBlock(javaCodePrologue, 1)}[#rt]
        [#nested]
    [#else]
        [#-- We need tree nodes and/or recovery code. --]      
        [#if buildingTreeNode]
            [#-- Build the tree node (part 1). --]
            [@buildTreeNode production treeNodeBehavior nodeVarName /]
        [/#if]
        [#-- Any prologue code can refer to CURRENT_NODE at this point. --][#-- REVISIT: Is this needed anymore, since thisProduction is always the reference to CURRENT_NODE (jb)? --]
${globals.translateCodeBlock(javaCodePrologue, 1)}
ParseException ${parseExceptionVar} = null;
var ${callStackSizeVar} = ParsingStack.Count;
try {
        [#--     pass  # in case there's nothing else in the try clause! --]
        [#-- Here is the "nut". --]
        [#nested]
}
catch (ParseException e) {
    ${parseExceptionVar} = e;
        [#if !canRecover]
            [#if settings.faultTolerant]
    if (IsTolerant) _pendingRecovery = true;
            [/#if]
    throw;
        [#else]
    if (!IsTolerant) throw;
    _pendingRecovery = true;
         ${expansion.customErrorRecoveryBlock!}
            [#if !production?is_null && production.returnType != "void"]
                [#var rt = production.returnType]
                [#-- We need a return statement here or the code won't compile! --]
                [#if rt = "int" || rt="char" || rt=="byte" || rt="short" || rt="long" || rt="float"|| rt="double"]
       return 0;
                [#else]
       return null;
                [/#if]
            [/#if]
        [/#if]
}
finally {
    RestoreCallStack(${callStackSizeVar});
[#if buildingTreeNode]
    [#-- Build the tree node (part 2). --]
    [@buildTreeNodeEpilogue treeNodeBehavior nodeVarName parseExceptionVar /]
[/#if]
    _currentlyParsedProduction = prevProduction;
}
[/#if]
[#-- // DBG < TreeBuildingAndRecovery --]
[/#macro]

[#function imputedJtbFieldName nodeClass]
   [#if nodeClass?? && jtbParseTree && topLevelExpansion]
      [#-- Determine the name of the node field containing the reference to a synthetic syntax node --]
      [#var fieldName = nodeClass?uncap_first]
      [#var fieldOrdinal]
      [#if jtbNameMap[nodeClass]??] 
         [#-- Allow for JTB-style syntactic node names (but exclude Token and <non-terminal> ). --]
         [#set fieldName = jtbNameMap[nodeClass]/]
      [/#if]
      [#set fieldOrdinal = nodeFieldOrdinal[nodeClass]!null]
      [#if fieldOrdinal?is_null]
         [#set nodeFieldOrdinal = nodeFieldOrdinal + {nodeClass : 1}]
      [#else]
         [#set nodeFieldOrdinal = nodeFieldOrdinal + {nodeClass : fieldOrdinal + 1}]
      [/#if]
      [#var nodeFieldName = fieldName + fieldOrdinal!""]
      [#-- INJECT <production-node> : { public <field-type> <unique-field-name> } --]
      ${injectDeclaration(nodeClass, nodeFieldName)}
      [#return nodeFieldName/]
   [/#if]
   [#-- Indicate that no field name is required (either not JTB or not a top-level production node) --]
   [#return null/]
[/#function]

[#function resolveTreeNodeBehavior expansion]
   [#var treeNodeBehavior = expansion.treeNodeBehavior]
   [#var isProduction = false]
   [#if expansion.simpleName = "BNFProduction"]
      [#set isProduction = true]
   [#else]
      [#var nodeName = syntacticNodeName(expansion)] [#-- This maps ExpansionSequence containing more than one syntax element to "Sequence", otherwise to the element itself --]
      [#if !treeNodeBehavior?? &&
           expansion.assignment??
      ]
         [#if syntheticNodesEnabled && isProductionInstantiatingNode(expansion)]
            [#-- Assignment is explicitly provided and synthetic nodes are enabled --]
            [#-- NOTE: An explicit assignment will take precedence over a synthetic JTB node. 
               I.e., it will not create a field in the production node.  It WILL, however, 
               use the syntactic node type for the natural assignment value, as seen below.  
            --]
            [#-- This expansion has an explicit assignment; check if we need to synthesize a definite node --]
            [#if nodeName?? && (
               nodeName == "ZeroOrOne" ||
               nodeName == "ZeroOrMore" ||
               nodeName == "OneOrMore" ||
               nodeName == "Choice" ||
               nodeName == "Sequence"
               )
            ]
               [#-- We do need to create a definite node --]
               [#if !jtbParseTree]
                  [#-- It's not a JTB tree, so use the BASE_NODE type for type for assignment rather than syntactic type --][#-- (jb) is there a reason to use the syntactic type always?  Perhaps, but I can't think of one. --]
                  [#set nodeName = settings.baseNodeClassName]
               [/#if]
               [#-- Make a new node to wrap the current expansion with the expansion's assignment. --]
               [#set treeNodeBehavior = {
                                          'nodeName' : nodeName, 
                                          'condition' : null, 
                                          'gtNode' : false,
                                          'void' : false,
                                          'assignment' : expansion.assignment
                                       } /]
               [#if expansion.assignment.propertyAssignment && !expansion.assignment.noAutoDefinition]
                  [#-- Inject the receiving property --]
                  ${injectDeclaration(nodeName, expansion.assignment.name, expansion.assignment)}
               [/#if]
            [/#if]
         [#elseif nodeName??]
            [#-- We are attempting to do assignment of a syntactic node value, but synthetic nodes are not enabled --]
            [#-- FIXME: we should probably create treeNodeBehavior that signals this error to somebody that can report it to the user --]
            [#return null /]
         [/#if]
      [#elseif treeNodeBehavior?? &&
               treeNodeBehavior.assignment?? &&
               isProductionInstantiatingNode(expansion)]
         [#-- There is an explicit tree node annotation with assignment; make sure a property is injected if needed. --]
         [#if !treeNodeBehavior.assignment.noAutoDefinition]
            ${injectDeclaration(treeNodeBehavior.nodeName, treeNodeBehavior.assignment.name, treeNodeBehavior.assignment)}
         [/#if]
      [#elseif jtbParseTree && expansion.parent.simpleName != "ExpansionWithParentheses" && isProductionInstantiatingNode(expansion)]
         [#-- No in-line definite node annotation; synthesize a parser node for the expansion type being built, if needed. --]
         [#if nodeName??]
            [#-- Determine the node name depending on syntactic type --]
            [#var nodeFieldName = imputedJtbFieldName(nodeName)] [#-- Among other things this injects the node field into the generated node if result is non-nullv--]
            [#-- Default to always produce a node even if no child nodes --]
            [#var gtNode = false]
            [#var condition = null]
            [#var initialShorthand = null]
            [#if nodeName == "Choice"]
               [#-- Generate a Choice node only if at least one child node --]
               [#set gtNode = true]
               [#set condition = "0"]
               [#set initialShorthand = " > "]
            [/#if]
            [#if nodeFieldName??]
               [#-- Provide an assignment to save the syntactic node in a 
               synthetic field injected into the actual production node per JTB behavior. --]
               [#set treeNodeBehavior = {
                                    'nodeName' : nodeName!"nemo", 
                                    'condition' : condition, 
                                    'gtNode' : gtNode, 
                                    'initialShorthand' : initialShorthand,
                                    'void' : false,
                                    'assignment' : 
                                       { 'name' : "thisProduction." + nodeFieldName, 
                                          'propertyAssignment' : false, 
                                          'noAutoDefinition' : false,
                                          'existenceOf' : false }
                                 } /]
            [#else]
               [#-- Just provide the syntactic node with no LHS needed --]
               [#set treeNodeBehavior = {
                                          'nodeName' : nodeName!"nemo",  
                                          'condition' : condition, 
                                          'gtNode' : gtNode, 
                                          'initialShorthand' : initialShorthand,
                                          'void' : false,
                                          'assignment' : null
                                       } /]
            [/#if]
         [/#if]
      [/#if]
   [/#if]
   [#if !treeNodeBehavior??]
      [#-- There is still no express treeNodeBehavior determined; supply the default if this is a BNF production node --]  
      [#if isProduction && !settings.nodeDefaultVoid 
                        && !grammar.nodeIsInterface(expansion.name)
                        && !grammar.nodeIsAbstract(expansion.name)]
         [#if settings.smartNodeCreation]
            [#set treeNodeBehavior = {"nodeName" : expansion.name!"nemo", "condition" : "1", "gtNode" : true, "void" :false, "initialShorthand" : ">"}]
         [#else]
            [#set treeNodeBehavior = {"nodeName" : expansion.name!"nemo", "condition" : null, "gtNode" : false, "void" : false}]
         [/#if]
      [/#if]
   [/#if]
   [#if treeNodeBehavior?? && treeNodeBehavior.neverInstantiated?? && treeNodeBehavior.neverInstantiated]
      [#-- Now, if the treeNodeBehavior says it will never be instantiated, throw it all away --]
      [#return null/]
   [/#if]
   [#-- This is the actual treeNodeBehavior for this node --]
   [#return treeNodeBehavior]
[/#function]

[#-- This is primarily to distinguish sequences of syntactic elements from effectively single elements --]
[#function syntacticNodeName expansion]
      [#var classname = expansion.simpleName]
      [#if classname = "ZeroOrOne"]
         [#return classname/]
      [#elseif classname = "ZeroOrMore"]
         [#return classname/]
      [#elseif classname = "OneOrMore"]
         [#return classname/]
      [#elseif jtbParseTree && classname = "Terminal"]
         [#return classname/]
      [#elseif classname = "ExpansionChoice"]
         [#return "Choice"/]
      [#elseif classname = "ExpansionWithParentheses" || classname = "BNFProduction"]
         [#-- the () will be skipped and the nested expansion processed, so built the tree node for it rather than this --]
         [#var innerExpansion = expansion.nestedExpansion/]
         [#return syntacticNodeName(innerExpansion)/]
      [#elseif classname = "ExpansionSequence" && 
               expansion.parent?? &&
               (
                  expansion.parent.simpleName == "ExpansionWithParentheses" ||
                  (
                     expansion.parent.simpleName == "ZeroOrOne" ||
                     expansion.parent.simpleName == "OneOrMore" ||
                     expansion.parent.simpleName == "ZeroOrMore" ||
                     expansion.parent.simpleName == "ExpansionChoice"
                  ) && expansion.essentialSequence
               )]
         [#return "Sequence"/]
      [/#if]
      [#return null/]
[/#function]

[#function isProductionInstantiatingNode expansion] 
   [#if expansion.containingProduction.treeNodeBehavior?? && 
        expansion.containingProduction.treeNodeBehavior.neverInstantiated!false]
      [#return false/]
   [/#if]
   [#return true/]
[/#function]

[#function nodeVar isProduction]
   [#var nodeVarName]
   [#if isProduction]
      [#set nodeVarName = "thisProduction"] [#-- [JB] maybe should be "CURRENT_PRODUCTION" or "THIS_PRODUCTION" to match "CURRENT_NODE"? --]
   [#else]
      [#set nodeNumbering = nodeNumbering +1]
      [#set nodeVarName = currentProduction.name + nodeNumbering] 
   [/#if]
   [#return nodeVarName/]
[/#function]

[#macro buildTreeNode production treeNodeBehavior nodeVarName] [#-- FIXME: production is not used here --]
   ${globals.pushNodeVariableName(nodeVarName)!}
   [@createNode nodeClassName(treeNodeBehavior) nodeVarName /]
[/#macro]

[#--  Boilerplate code to create the node variable --]
[#macro createNode nodeClass nodeVarName]
[#-- // DBG > createNode --]
${nodeClass} ${nodeVarName} = null;
if (BuildTree) {
    ${nodeVarName} = new ${nodeClass}([#if settings.nodeUsesParser]this[#else]tokenSource[/#if]);
    OpenNodeScope(${nodeVarName});
}
[#-- // DBG < createNode --]
[/#macro]

[#macro buildTreeNodeEpilogue treeNodeBehavior nodeVarName parseExceptionVar]
   if (${nodeVarName}!=null) {
      if (${parseExceptionVar} == null) {
   [#if treeNodeBehavior?? && treeNodeBehavior.assignment??]
      [#var LHS = getLhsPattern(treeNodeBehavior.assignment, null)]
         if (CloseNodeScope(${nodeVarName}, ${closeCondition(treeNodeBehavior)})) {
            ${LHS?replace("@", "(" + nodeClassName(treeNodeBehavior) + ") PeekNode()")};
         } else{
            ${LHS?replace("@", "null")};
         }
   [#else]
         CloseNodeScope(${nodeVarName}, ${closeCondition(treeNodeBehavior)}); 
   [/#if]
   [#list grammar.closeNodeHooksByClass[nodeClassName(treeNodeBehavior)]! as hook]
         ${hook}(${nodeVarName});
   [/#list]
      } else {
   [#if settings.faultTolerant]
         CloseNodeScope(${nodeVarName}, true);
         ${nodeVarName}.dirty = true;
   [#else]
         ClearNodeScope();
   [/#if]
      }
   }
   ${globals.popNodeVariableName()!}
[/#macro]

[#function getRhsAssignmentPattern assignment] 
   [#if assignment.existenceOf!false]
      [#-- replace "@" with "((@ != null) ? true : false)" --]
      [#return "((@ != null) ? true : false)" /]
   [#elseif assignment.stringOf!false]
      [#-- replace "@" with the string value of the node --]
      [#return "((@ != null) ? String.ValueOf(@) : null)"]
   [/#if]
   [#return "@" /]
[/#function]

[#function getLhsPattern assignment, lhsType]
   [#if assignment??]
      [#var lhsName = assignment.name]
      [#if assignment.propertyAssignment]
         [#-- This is the assignment of the current node's effective value to a property of the production node --]
         [#set lhsName = lhsName?cap_first]
         [#if lhsType?? && !assignment.noAutoDefinition]
            [#-- This is a declaration assignment; inject required property --]
            ${injectDeclaration(lhsType, assignment.name, assignment)}
         [/#if]
         [#if assignment.addTo!false]
            [#-- This is the addition of the current node as a child of the specified property's node value --]
            [#return "thisProduction." + lhsName + ".AddChild(" + getRhsAssignmentPattern(assignment) + ")" /]
         [#else]
            [#-- This is an assignment of the current node's effective value to the specified property of the production node --]
            [#return "thisProduction." + lhsName + " = " + getRhsAssignmentPattern(assignment) /]
         [/#if]
      [#elseif assignment.namedAssignment!false]
         [#if assignment.addTo]
            [#-- This is the addition of the current node to the named child list of the production node --]
            [#return "thisProduction.AddToNamedChildList(\"" + lhsName + "\", " + getRhsAssignmentPattern(assignment) + ")" /]
         [#else]
            [#-- This is an assignment of the current node to a named child of the production node --]
            [#return "thisProduction.SetNamedChild(\"" + lhsName + "\", " + getRhsAssignmentPattern(assignment) + ")" /]
         [/#if]
      [/#if]
      [#-- This is the assignment of the current node or it's returned value to an arbitrary LHS "name" (i.e., the legacy JavaCC assignment) --]
      [#return lhsName + " = " + getRhsAssignmentPattern(assignment) /]
   [/#if]
   [#-- There is no LHS --]
   [#return "@" /]
[/#function]

[#function injectDeclaration typeName, fieldName, assignment]
   [#var modifier = "public"]
   [#var type = typeName]
   [#var field = fieldName]
   [#if assignment?? && assignment.propertyAssignment]
      [#set modifier = "@Property"]
   [/#if]
   [#if assignment?? && assignment.existenceOf] 
      [#set type = "bool"]
   [#elseif assignment?? && assignment.stringOf]
      [#set type = "string"]
   [/#if]
   ${grammar.addFieldInjection(currentProduction.nodeName, modifier, type, field)}
   [#return "" /]
[/#function]

[#function closeCondition treeNodeBehavior]
   [#var cc = "true"]
   [#if treeNodeBehavior??]
      [#if treeNodeBehavior.condition?has_content]
         [#set cc = treeNodeBehavior.condition]
         [#if treeNodeBehavior.gtNode]
            [#set cc = "NodeArity " + treeNodeBehavior.initialShorthand  + cc]
         [/#if]
      [/#if]
   [/#if]
   [#return cc/]
[/#function]

[#function nodeClassName treeNodeBehavior]
   [#if treeNodeBehavior?? && treeNodeBehavior.nodeName??]
      [#return NODE_PREFIX + treeNodeBehavior.nodeName]
   [/#if]
   [#return NODE_PREFIX + currentProduction.name]
[/#function]

[#macro BuildExpansionCode expansion]
   [#var classname=expansion.simpleName]
   [#var prevLexicalStateVar = CU.newVarName("previousLexicalState")]
   [#-- take care of the non-tree-building classes --]
   [#if classname = "CodeBlock"]
${globals.translateCodeBlock(expansion, 1)}
   [#-- OMITTED: [#elseif classname = "UncacheTokens"]
         uncacheTokens(); --]
   [#elseif classname = "Failure"]
      [@BuildCodeFailure expansion/]
   [#elseif classname = "Assertion"]
      [@BuildAssertionCode expansion/]
   [#elseif classname = "TokenTypeActivation"]
      [@BuildCodeTokenTypeActivation expansion/]
   [#elseif classname = "TryBlock"]
      [@BuildCodeTryBlock expansion/]
   [#elseif classname = "AttemptBlock"]
      [@BuildCodeAttemptBlock expansion/]
   [#else]
      [#-- take care of the tree node (if any) --]
      [@TreeBuildingAndRecovery expansion]
         [#if classname = "BNFProduction"]
            [#-- The tree node having been built, now build the actual top-level expansion --]
            [#set topLevelExpansion = true]
            // top-level expansion ${expansion.nestedExpansion.simpleName}
            [@BuildCode expansion.nestedExpansion/]
         [#else]
            [#-- take care of terminal and non-terminal expansions; they cannot contain child expansions --]
            [#if classname = "NonTerminal"]
               [@BuildCodeNonTerminal expansion/]
            [#elseif classname = "Terminal"]
               [@BuildCodeTerminal expansion/]
            [#else]
               [#-- take care of the syntactical expansions (which can contain child expansions) --]
               [#-- capture the top-level indication in order to restore when bubbling up --]
               [#var stackedTopLevel = topLevelExpansion]
               [#if topLevelExpansion && classname != "ExpansionSequence"]
                  [#-- turn off top-level indication unless an expansion sequence (the tree node has already been determined when this nested template is expanded) --]
                  [#set topLevelExpansion = false]
               [/#if]
               [#if classname = "ZeroOrOne"]
                  [@BuildCodeZeroOrOne expansion/]
               [#elseif classname = "ZeroOrMore"]
                  [@BuildCodeZeroOrMore expansion/]
               [#elseif classname = "OneOrMore"]
                  [@BuildCodeOneOrMore expansion/]
               [#elseif classname = "ExpansionChoice"]
                  [@BuildCodeChoice expansion/]
               [#elseif classname = "ExpansionWithParentheses"]
                  [#-- Recurse; the real expansion is nested within this one (but the LHS, if any, is on the parent) --]
                  [@BuildExpansionCode expansion.nestedExpansion/]
               [#elseif classname = "ExpansionSequence"]
                  [@BuildCodeSequence expansion /] [#-- leave the topLevelExpansion one-shot alone (see above) --]
               [/#if]
               [#set topLevelExpansion = stackedTopLevel]
            [/#if]
         [/#if]
      [/@TreeBuildingAndRecovery]
   [/#if]
[/#macro]

[#macro BuildCodeFailure fail]
[#-- // DBG > BuildCodeFailure --]
    [#if fail.code?is_null]
      [#if fail.exp??]
Fail("Failure: " + ${fail.exp});
      [#else]
Fail("Failure");
      [/#if]
    [#else]
${globals.translateCodeBlock(fail.code, 1)}
    [/#if]
[#-- // DBG < BuildCodeFailure --]
[/#macro]

[#macro BuildAssertionCode assertion]
[#var optionalPart = ""]
[#if assertion.messageExpression??]
  [#set optionalPart = " + " + globals.translateExpression(assertion.messageExpression)]
[/#if]
   [#var assertionMessage = "Assertion at: " + assertion.location?j_string + " failed. "]
   [#if assertion.assertionExpression??]
if (!(${globals.translateExpression(assertion.assertionExpression)})) {
    Fail("${assertionMessage}"${optionalPart});
}
   [/#if]
   [#if assertion.expansion??]
if ([#if !assertion.expansionNegated]![/#if]${assertion.expansion.scanRoutineName}()) {
    Fail("${assertionMessage}"${optionalPart});
}
   [/#if]
[/#macro]

[#macro BuildCodeTokenTypeActivation activation]
[#-- // DBG > BuildCodeTokenTypeActivation --]
[#if activation.deactivate]
DeactivateTokenTypes(
[#else]
ActivateTokenTypes(
[/#if]
[#list activation.tokenNames as name]
    ${name}[#if name_has_next],[/#if]
[/#list]
);
[#-- // DBG < BuildCodeTokenTypeActivation --]
[/#macro]

[#macro BuildCodeTryBlock tryblock]
// DBG > BuildCodeTryBlock
try:
${BuildCode(tryblock.nestedExpansion)}
   [#list tryblock.catchBlocks as catchBlock]
${catchBlock}
   [/#list]
${tryblock.finallyBlock!}
// DBG < BuildCodeTryBlock
[/#macro]

[#macro BuildCodeAttemptBlock attemptBlock]
// DBG > BuildCodeAttemptBlock
try {
    StashParseState();
${BuildCode(attemptBlock.nestedExpansion)}
    PopParseState();
}
catch (ParseException) {
    RestoreStashedParseState();
${BuildCode(attemptBlock.recoveryExpansion)}
}
// DBG < BuildCodeAttemptBlock
[/#macro]

[#-- The following macros build expansions that might build tree nodes (could be called "syntactic" nodes). --]

[#macro BuildCodeNonTerminal nonterminal]
[#-- // DBG > BuildCodeNonTerminal ${nonterminal.production.name} --]
   [#var production = nonterminal.production]
PushOntoCallStack("${nonterminal.containingProduction.name}", "${nonterminal.inputSource?j_string}", ${nonterminal.beginLine}, ${nonterminal.beginColumn});
   [#var followSet = nonterminal.followSet]
   [#if !followSet.incomplete]
      [#if !nonterminal.beforeLexicalStateSwitch]
OuterFollowSet = ${nonterminal.followSetVarName};
      [#else]
OuterFollowSet = null;
      [/#if]
   [#else]
     [#if !followSet.isEmpty()]
if (OuterFollowSet != null) {
    var newFollowSet = new HashSet<TokenType>(${nonterminal.followSetVarName});
    newFollowSet.UnionWith(OuterFollowSet);
    OuterFollowSet = newFollowSet;
}
     [/#if]
   [/#if]
try {
    [@AcceptNonTerminal nonterminal /]
}
finally {
    PopCallStack();
}
[#-- // DBG < BuildCodeNonTerminal${nonterminal.production.name} --]
[/#macro]

[#macro AcceptNonTerminal nonterminal]
   [#var lhsClassName = nonterminal.production.nodeName]
   [#var expressedLHS = getLhsPattern(nonterminal.assignment, lhsClassName)]
   [#var impliedLHS = "@"]
   [#if jtbParseTree && isProductionInstantiatingNode(nonterminal.nestedExpansion) && topLevelExpansion]
      [#set impliedLHS = "thisProduction.${imputedJtbFieldName(nonterminal.production.nodeName)} = @"]
   [/#if]
   [#-- Accept the non-terminal expansion --]
   [#if nonterminal.production.returnType != "void" && expressedLHS != "@"]
      [#-- Not a void production, so accept and clear the expressedLHS, it has already been applied. --]
      ${expressedLHS?replace("@", "Parse" + nonterminal.name + "(" + globals.translateNonterminalArgs(nonterminal.args)! + ")")};
      [#set expressedLHS = "@"]
   [#else]
      Parse${nonterminal.name}(${globals.translateNonterminalArgs(nonterminal.args)!});
   [/#if]
   [#if expressedLHS != "@" || impliedLHS != "@"]
      [#if nonterminal.assignment?? && (nonterminal.assignment.addTo!false || nonterminal.assignment.namedAssignment)]
         if (BuildTree) {
            ${expressedLHS?replace("@", impliedLHS?replace("@", "PeekNode()"))};
         }
      [#else]
         try {
            [#-- There had better be a node here! --]
            ${expressedLHS?replace("@", impliedLHS?replace("@", "(" + nonterminal.production.nodeName + ") PeekNode()"))};
         } catch (InvalidCastException) {
            ${expressedLHS?replace("@", impliedLHS?replace("@", "null"))};
         }
      [/#if]
   [/#if]
   [#if nonterminal.childName??]
      if (BuildTree) {
         Node child = PeekNode();
         String name = "${nonterminal.childName}";
      [#if nonterminal.multipleChildren]
         ${globals.currentNodeVariableName}.AddToNamedChildList(name, child);
      [#else]
         ${globals.currentNodeVariableName}.SetNamedChild(name, child);
      [/#if]
      }
   [/#if] 
[/#macro]

[#macro BuildCodeTerminal terminal]
   [#var LHS = getLhsPattern(terminal.assignment, "Token"), regexp=terminal.regexp]
[#-- // DBG > BuildCodeRegexp --]
   [#if !settings.faultTolerant]
${LHS?replace("@", "ConsumeToken(" + CU.TT + regexp.label + ")")};
   [#else]
       [#var tolerant = terminal.tolerantParsing?string("true", "false")]
       [#var followSetVarName = terminal.followSetVarName]
       [#if terminal.followSet.incomplete]
         [#set followSetVarName = "followSet" + CU.newID()]
HashSet<TokenType> ${followSetVarName} = null;
if (OuterFollowSet != null) {
    ${followSetVarName} = ${terminal.followSetVarName}.Clone();
    ${followSetVarName}.AddAll(OuterFollowSet);
}
       [/#if]
${LHS?replace("@", "ConsumeToken(" + CU.TT + regexp.label + ", " + tolerant + ", " + followSetVarName + ")")};
   [/#if]
   [#if !terminal.childName?is_null && !globals.currentNodeVariableName?is_null]
if (BuildTree) {
    Node child = PeekNode();
    string name = "${terminal.childName}";
    [#if terminal.multipleChildren]
    ${globals.currentNodeVariableName}.AddToNamedChildList(name, child);
    [#else]
    ${globals.currentNodeVariableName}.SetNamedChild(name, child);
    [/#if]
}
   [/#if]
[#-- // DBG < BuildCodeRegexp --]
[/#macro]

[#macro BuildCodeZeroOrOne zoo]
[#-- // DBG > BuildCodeZeroOrOne ${zoo.nestedExpansion.class.simpleName} --]
    [#if zoo.nestedExpansion.class.simpleName = "ExpansionChoice"]
${BuildCode(zoo.nestedExpansion)}
    [#else]
if (${ExpansionCondition(zoo.nestedExpansion)}) {
${BuildCode(zoo.nestedExpansion)}
}
    [/#if]
[#-- // DBG < BuildCodeZeroOrOne ${zoo.nestedExpansion.class.simpleName} --]
[/#macro]

[#var inFirstVarName = "", inFirstIndex =0]

[#macro BuildCodeOneOrMore oom]
[#-- // DBG > BuildCodeOneOrMore --]
[#var nestedExp=oom.nestedExpansion, prevInFirstVarName = inFirstVarName/]
   [#if nestedExp.simpleName = "ExpansionChoice"]
     [#set inFirstVarName = "inFirst" + inFirstIndex, inFirstIndex = inFirstIndex +1 /]
var ${inFirstVarName} = true;
   [/#if]
while (true) {
${RecoveryLoop(oom)}
      [#if nestedExp.simpleName = "ExpansionChoice"]
    ${inFirstVarName} = false;
      [#else]
    if (!(${ExpansionCondition(oom.nestedExpansion)})) break;
      [/#if]
}
   [#set inFirstVarName = prevInFirstVarName /]
[#-- // DBG < BuildCodeOneOrMore --]
[/#macro]

[#macro BuildCodeZeroOrMore zom]
[#-- // DBG > BuildCodeZeroOrMore --]
while (true) {
       [#if zom.nestedExpansion.class.simpleName != "ExpansionChoice"]
    if (!(${ExpansionCondition(zom.nestedExpansion)})) break;
       [/#if]
       [@RecoveryLoop zom /]
}
[#-- // DBG < BuildCodeZeroOrMore --]
[/#macro]

[#macro RecoveryLoop loopExpansion]
[#-- // DBG > RecoveryLoop --]
[#if !settings.faultTolerant || !loopExpansion.requiresRecoverMethod]
${BuildCode(loopExpansion.nestedExpansion)}
[#else]
[#var initialTokenVarName = "initialToken" + CU.newID()]
${initialTokenVarName} = LastConsumedToken;
try {
${BuildCode(loopExpansion.nestedExpansion)}
}
catch (ParseException pe) {
    if (!IsTolerant) throw;
    if (debugFaultTolerant) {
        // logger.info('Handling exception. Last consumed token: %s at: %s', lastConsumedToken.image, lastConsumedToken.location)
    }
    if (${initialTokenVarName} == LastConsumedToken) {
        LastConsumedToken = NextToken(LastConsumedToken);
        // We have to skip a token in this spot or
        // we'll be stuck in an infinite loop!
        LastConsumedToken.skipped = true;
        if (debugFaultTolerant) {
            // logger.info('Skipping token %s at: %s', lastConsumedToken.image, lastConsumedToken.location)
        }
    }
    if (debugFaultTolerant) {
        // logger.info('Repeat re-sync for expansion at: ${loopExpansion.location?j_string}');
    }
    ${loopExpansion.recoverMethodName}();
    if (pendingRecovery) throw;
   [/#if]
[#-- // DBG < RecoveryLoop --]
[/#macro]

[#macro BuildCodeChoice choice]
[#-- // DBG > BuildCodeChoice  --]
   [#list choice.choices as expansion]
   [#-- OMITTED:
      [#if expansion.enteredUnconditionally]
        {
         // choice for ${globals.currentNodeVariableName} index ${expansion_index}
         ${BuildCode(expansion)}
         [#if jtbParseTree && isProductionInstantiatingNode(expansion)]
            ${globals.currentNodeVariableName}.setChoice(${expansion_index});
         [/#if]
        }
        [#if expansion_has_next]
            [#var nextExpansion = choice[expansion_index+1]]
            // Warning: choice at ${nextExpansion.location} is is ignored because the 
            // choice at ${expansion.location} is entered unconditionally and we jump
            // out of the loop.. 
        [/#if]
         [#return/]
      [/#if]
   --]
${(expansion_index=0)?string("if", "else if")} (${ExpansionCondition(expansion)}) {
${BuildCode(expansion)}
      [#if jtbParseTree && isProductionInstantiatingNode(expansion)]
         ${globals.currentNodeVariableName}.setChoice(${expansion_index});
      [/#if]
}
   [/#list]
   [#if choice.parent.simpleName == "ZeroOrMore"]
else {
    break;
}
   [#elseif choice.parent.simpleName = "OneOrMore"]
else if (${inFirstVarName}) {
    PushOntoCallStack("${currentProduction.name}", "${choice.inputSource?j_string}", ${choice.beginLine}, ${choice.beginColumn});
    throw new ParseException(this, ${choice.firstSetVarName});
}
else {
    break;
}
   [#elseif choice.parent.simpleName != "ZeroOrOne"]
else {
    PushOntoCallStack("${currentProduction.name}", "${choice.inputSource?j_string}", ${choice.beginLine}, ${choice.beginColumn});
    throw new ParseException(this, ${choice.firstSetVarName});
}
   [/#if]
[#-- // DBG < BuildCodeChoice --]
[/#macro]

[#macro BuildCodeSequence expansion]
[#-- // DBG > BuildCodeSequence --]
  [#list expansion.units as subexp]
${BuildCode(subexp)}
  [/#list]
[#-- // DBG < BuildCodeSequence --]
[/#macro]

[#-- The following is a set of utility macros used in expansions. --]

[#--
     Macro to generate the condition for entering an expansion
     including the default single-token lookahead
--]
[#macro ExpansionCondition expansion]
[#if expansion.requiresPredicateMethod]${ScanAheadCondition(expansion)}[#else]${SingleTokenCondition(expansion)}[/#if]
[/#macro]

[#-- Generates code for when we need a scanahead --]
[#macro ScanAheadCondition expansion]
[#if expansion.lookahead?? && expansion.lookahead.assignment??](${expansion.lookahead.assignment.name} = [/#if][#if expansion.hasSemanticLookahead && !expansion.lookahead.semanticLookaheadNested](${globals.translateExpression(expansion.semanticLookahead)}) && [/#if]${expansion.predicateMethodName}()[#if expansion.lookahead?? && expansion.lookahead.assignment??])[/#if]
[/#macro]


[#-- Generates code for when we don't need any scanahead routine --]
[#macro SingleTokenCondition expansion]
   [#if expansion.hasSemanticLookahead](${globals.translateExpression(expansion.semanticLookahead)}) && [/#if]
   [#if expansion.firstSet.tokenNames?size = 0 || expansion.lookaheadAmount ==0 || expansion.minimumSize=0]true[#elseif expansion.firstSet.tokenNames?size < 5][#list expansion.firstSet.tokenNames as name](NextTokenType == TokenType.${name})[#if name_has_next] || [/#if][/#list][#else](${expansion.firstSetVarName}.Contains(NextTokenType))[/#if]
[/#macro]
