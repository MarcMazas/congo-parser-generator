 /* 
  * Generated by: ${generated_by}. ${filename} ${grammar.copyrightBlurb}
  */
package ${grammar.parserPackage};

[#if grammar.treeBuildingEnabled]
import ${grammar.nodePackage}.*;
[/#if]

import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;

[#if grammar.rootAPIPackage?has_content]
import ${grammar.rootAPIPackage}.Node;
[/#if]

[#if grammar.settings.FREEMARKER_NODES?? && grammar.settings.FREEMARKER_NODES]
import freemarker.template.*;
[/#if]

[#var implementsNode = ""]

 [#if grammar.treeBuildingEnabled]
    [#set implementsNode ="implements Node.TerminalNode"]
    [#if grammar.rootAPIPackage?has_content]
       import ${grammar.rootAPIPackage}.Node;
    [/#if]
 [/#if]

public class Token ${implementsNode} {

    public enum TokenType 
    [#if grammar.treeBuildingEnabled]
       implements Node.NodeType
    [/#if]
    {
       [#list grammar.lexerData.regularExpressions as regexp]
          ${regexp.label},
       [/#list]
       [#list grammar.extraTokenNames as extraToken]
          ${extraToken},
       [/#list]
       DUMMY,
       INVALID;

       public boolean isUndefined() {return this == DUMMY;}
       public boolean isInvalid() {return this == INVALID;}
       public boolean isEOF() {return this == EOF;}
    }    

    private ${grammar.lexerClassName} tokenSource;
    
    private TokenType type=TokenType.DUMMY;
    
    private int beginOffset, endOffset;
    
    private boolean unparsed;

[#if grammar.treeBuildingEnabled]
    private Node parent;
[/#if]

[#if !grammar.minimalToken || grammar.faultTolerant]
    private String image;
    public void setImage(String image) {
       this.image = image;
    }
[/#if]

[#if !grammar.minimalToken]

    private Token prependedToken, appendedToken;

    private boolean inserted;

    public boolean isInserted() {return inserted;}


    public void preInsert(Token prependedToken) {
        if (prependedToken == this.prependedToken) return;
        prependedToken.appendedToken = this;
        Token existingPreviousToken = this.previousCachedToken();
        if (existingPreviousToken != null) {
            existingPreviousToken.appendedToken = prependedToken;
            prependedToken.prependedToken = existingPreviousToken;
        }
        prependedToken.inserted = true;
        prependedToken.beginOffset = prependedToken.endOffset = this.beginOffset;
        this.prependedToken = prependedToken;
    }
    void unsetAppendedToken() {
        this.appendedToken = null;
    }

    /**
     * @param type the #TokenType of the token being constructed
     * @param image the String content of the token
     * @param tokenSource the object that vended this token.
     */
    public Token(TokenType type, String image, ${grammar.lexerClassName} tokenSource) {
        this.type = type;
        this.image = image;
        this.tokenSource = tokenSource;
    }

    public static Token newToken(TokenType type, String image, ${grammar.lexerClassName} tokenSource) {
        Token result = newToken(type, tokenSource, 0, 0);
        result.setImage(image);
        return result;
    }
[/#if]

    /**
     * It would be extremely rare that an application
     * programmer would use this method. It needs to
     * be public because it is part of the ${grammar.parserPackage}.Node interface.
     */
    public void setBeginOffset(int beginOffset) {
        this.beginOffset = beginOffset;
    }

    /**
     * It would be extremely rare that an application
     * programmer would use this method. It needs to
     * be public because it is part of the ${grammar.parserPackage}.Node interface.
     */
    public void setEndOffset(int endOffset) {
        this.endOffset = endOffset;
    }

    /**
     * @return the ${grammar.lexerClassName} object that handles 
     * location info for the tokens. 
     */
    public ${grammar.lexerClassName} getTokenSource() {
        return this.tokenSource; 
    }

    /**
     * It should be exceedingly rare that an application
     * programmer needs to use this method.
     */
    public void setTokenSource(TokenSource tokenSource) {
        this.tokenSource = (${grammar.lexerClassName}) tokenSource;
    }

    /**
     * Return the TokenType of this Token object
     */
[#if grammar.treeBuildingEnabled]@Override[/#if]
    public TokenType getType() {
        return type;
    }

    protected void setType(TokenType type) {
        this.type=type;
    }

    /**
     * @return whether this Token represent actual input or was it inserted somehow?
     */
    public boolean isVirtual() {
        [#if grammar.faultTolerant]
            return virtual || type == TokenType.EOF;
        [#else]
            return type == TokenType.EOF;
        [/#if]
    }

    /**
     * @return Did we skip this token in parsing?
     */
    public boolean isSkipped() {
        [#if grammar.faultTolerant]
           return skipped;
        [#else]
           return false;
        [/#if]
    }


[#if grammar.faultTolerant]
    private boolean virtual, skipped, dirty;

    void setVirtual(boolean virtual) {
        this.virtual = virtual;
        if (virtual) dirty = true;
    }

    void setSkipped(boolean skipped) {
        this.skipped = skipped;
        if (skipped) dirty = true;
    }

    public boolean isDirty() {
        return dirty;
    }

    public void setDirty(boolean dirty) {
        this.dirty = dirty;
    }

[/#if]


[#if !grammar.treeBuildingEnabled]
 [#-- If tree building is enabled, we can simply use the default 
      implementation in the Node interface--]
    /**
     * @return the (1-based) line location where this Token starts
     */      
    public int getBeginLine() {
        ${grammar.lexerClassName} flm = getTokenSource();
        return flm == null ? 0 : flm.getLineFromOffset(getBeginOffset());                
    };

    /**
     * @return the (1-based) line location where this Token ends
     */
    public int getEndLine() {
        ${grammar.lexerClassName} flm = getTokenSource();
        return flm == null ? 0 : flm.getLineFromOffset(getEndOffset()-1);
    };

    /**
     * @return the (1-based) column where this Token starts
     */
    public int getBeginColumn() {
        ${grammar.lexerClassName} flm = getTokenSource();
        return flm == null ? 0 : flm.getCodePointColumnFromOffset(getBeginOffset());        
    };

    /**
     * @return the (1-based) column offset where this Token ends
     */ 
    public int getEndColumn() {
        ${grammar.lexerClassName} flm = getTokenSource();
        return flm == null ? 0 : flm.getCodePointColumnFromOffset(getEndOffset());
    }

    public String getInputSource() {
        ${grammar.lexerClassName} flm = getTokenSource();
        return flm != null ? flm.getInputSource() : "input";
    }
[/#if]    

    public int getBeginOffset() {
        return beginOffset;
    }

    public int getEndOffset() {
        return endOffset;
    }

    /**
     * @return the string image of the token.
     */
[#if grammar.treeBuildingEnabled]@Override[/#if]
    public String getImage() {
      [#if grammar.minimalToken]
        return getSource();
      [#else]  
        return image != null ? image : getSource();
      [/#if]
    }

    /**
     * @return the next _cached_ regular (i.e. parsed) token
     * or null
     */
    public final Token getNext() {
        return getNextParsedToken();
    }

    /**
     * @return the previous regular (i.e. parsed) token
     * or null
     */
    public final Token getPrevious() {
        Token result = previousCachedToken();
        while (result != null && result.isUnparsed()) {
            result = result.previousCachedToken();
        }
        return result;
    }

    /**
     * @return the next regular (i.e. parsed) token
     */
    private Token getNextParsedToken() {
        Token result = nextCachedToken();
        while (result != null && result.isUnparsed()) {
            result = result.nextCachedToken();
        }
        return result;
    }

    /**
     * @return the next token of any sort (parsed or unparsed or invalid)
     */
    public Token nextCachedToken() {
        if (getType() == TokenType.EOF) return null;
[#if !grammar.minimalToken]        
        if (appendedToken != null) return appendedToken;
[/#if]        
        ${grammar.lexerClassName} tokenSource = getTokenSource();
        return tokenSource != null ? (Token) tokenSource.nextCachedToken(getEndOffset()) : null;
    }

    public Token previousCachedToken() {
[#if !grammar.minimalToken]        
        if (prependedToken !=null) return prependedToken;
[/#if]        
        if (getTokenSource()==null) return null;
        return (Token) getTokenSource().previousCachedToken(getBeginOffset());
    }

    Token getPreviousToken() {
        return previousCachedToken();
    }

    public Token replaceType(TokenType type) {
        Token result = newToken(type, getTokenSource(), getBeginOffset(), getEndOffset());
[#if !grammar.minimalToken]        
        result.prependedToken = this.prependedToken;
        result.appendedToken = this.appendedToken;
        result.inserted = this.inserted;
        if (result.appendedToken != null) {
            result.appendedToken.prependedToken = result;
        }
        if (result.prependedToken != null) {
            result.prependedToken.appendedToken = result;
        }
        if (!result.inserted) {
            getTokenSource().cacheToken(result);
        }
[#else]
        getTokenSource().cacheToken(result);
[/#if]        

        return result;
    }

    public String getSource() {
         if (type == TokenType.EOF) return "";
         ${grammar.lexerClassName} flm = getTokenSource();
         return flm == null ? null : flm.getText(getBeginOffset(), getEndOffset());
    }



    protected Token() {}

    public Token(TokenType type, ${grammar.lexerClassName} tokenSource, int beginOffset, int endOffset) {
        this.type = type;
        this.tokenSource = tokenSource;
        this.beginOffset = beginOffset;
        this.endOffset = endOffset;
    }

    public boolean isUnparsed() {
        return unparsed;
    }

    public void setUnparsed(boolean unparsed) {
        this.unparsed = unparsed;
    }

    public void clearChildren() {}

    public String getNormalizedText() {
        if (getType() == TokenType.EOF) {
            return "EOF";
        }
        return getImage();
    }

    public String toString() {
        return getNormalizedText();
    }

    /**
     * @return An iterator of the tokens preceding this one.
     */
    public Iterator<Token> precedingTokens() {
        return new Iterator<Token>() {
            Token currentPoint = Token.this;
            public boolean hasNext() {
                return currentPoint.previousCachedToken() != null;
            }
            public Token next() {
                Token previous = currentPoint.previousCachedToken();
                if (previous == null) throw new java.util.NoSuchElementException("No previous token!");
                return currentPoint = previous;
            }
        };
    }

    /**
     * @return a list of the unparsed tokens preceding this one in the order they appear in the input
     */
    public List<Token> precedingUnparsedTokens() {
        List<Token> result = new ArrayList<>();
        Token t = this.previousCachedToken();
        while (t != null && t.isUnparsed()) {
            result.add(t);
            t = t.previousCachedToken();
        }
        Collections.reverse(result);
        return result;
    }

    /**
     * @return An iterator of the (cached) tokens that follow this one.
     */
    public Iterator<Token> followingTokens() {
        return new java.util.Iterator<Token>() {
            Token currentPoint = Token.this;
            public boolean hasNext() {
                return currentPoint.nextCachedToken() != null;
            }
            public Token next() {
                Token next= currentPoint.nextCachedToken();                
                if (next == null) throw new java.util.NoSuchElementException("No next token!");
                return currentPoint = next;
            }
        };
    }

[#if grammar.treeBuildingEnabled && !grammar.minimalToken]
    /**
     * Copy the location info from a Node
     */
    public void copyLocationInfo(Node from) {
        Node.TerminalNode.super.copyLocationInfo(from);
        if (from instanceof Token) {
            Token otherTok = (Token) from;
            appendedToken = otherTok.appendedToken;
            prependedToken = otherTok.prependedToken;
        }
        setTokenSource(from.getTokenSource());
    }
    
    public void copyLocationInfo(Node start, Node end) {
        Node.TerminalNode.super.copyLocationInfo(start, end);
        if (start instanceof Token) {
            prependedToken = ((Token) start).prependedToken;
        }
        if (end instanceof Token) {
            Token endToken = (Token) end;
            appendedToken = endToken.appendedToken;
        }
    }
[#else]
    public void copyLocationInfo(Token from) {
        setTokenSource(from.getTokenSource());
        setBeginOffset(from.getBeginOffset());
        setEndOffset(from.getEndOffset());
    [#if !grammar.minimalToken]    
        appendedToken = from.appendedToken;
        prependedToken = from.prependedToken;
    [/#if]
    }

    public void copyLocationInfo(Token start, Token end) {
        setTokenSource(start.getTokenSource());
        if (tokenSource == null) setTokenSource(end.getTokenSource());
        setBeginOffset(start.getBeginOffset());
        setEndOffset(end.getEndOffset());
    [#if !grammar.minimalToken]
        prependedToken = start.prependedToken;
        appendedToken = end.appendedToken;
    [/#if]
    }
[/#if]

    public static Token newToken(TokenType type, ${grammar.lexerClassName} tokenSource, int beginOffset, int endOffset) {
        [#if grammar.treeBuildingEnabled]
           switch(type) {
           [#list grammar.orderedNamedTokens as re]
            [#if re.generatedClassName != "Token" && !re.private]
              case ${re.label} : return new ${grammar.nodePrefix}${re.generatedClassName}(TokenType.${re.label}, tokenSource, beginOffset, endOffset);
            [/#if]
           [/#list]
           [#list grammar.extraTokenNames as tokenName]
              case ${tokenName} : return new ${grammar.nodePrefix}${grammar.extraTokens[tokenName]}(TokenType.${tokenName}, tokenSource, beginOffset, endOffset);
           [/#list]
              case INVALID : return new InvalidToken(tokenSource, beginOffset, endOffset);
              default : return new Token(type, tokenSource, beginOffset, endOffset);
           }
       [#else]
         return new Token(type, tokenSource, beginOffset, endOffset);
       [/#if]
    }

    public String getLocation() {
        return getInputSource() + ":" + getBeginLine() + ":" + getBeginColumn();
     }

[#if grammar.treeBuildingEnabled]

    public void setChild(int i, Node n) {
        throw new UnsupportedOperationException();
    }

    public void addChild(Node n) {
        throw new UnsupportedOperationException();
    }

    public void addChild(int i, Node n) {
        throw new UnsupportedOperationException();
    }

    public Node removeChild(int i) {
        throw new UnsupportedOperationException();
    }

    public final int indexOf(Node n) {
        return -1;
    }

    public Node getParent() {
        return parent;
    }

    public void setParent(Node parent) {
        this.parent = parent;
    }

    public final int getChildCount() {
        return 0;
    }

    public final Node getChild(int i) {
        return null;
    }

    public final List<Node> children() {
        return java.util.Collections.emptyList();
    }

   [#if grammar.settings.FREEMARKER_NODES?? && grammar.settings.FREEMARKER_NODES]
    public TemplateNodeModel getParentNode() {
        return parent;
    }

    public TemplateSequenceModel getChildNodes() {
        return null;
    }

    public String getNodeName() {
        return getType().toString();
    }

    public String getNodeType() {
        return getClass().getSimpleName();
    }

    public String getNodeNamespace() {
        return null;
    }

    public String getAsString() {
        return getNormalizedText();
    }
  [/#if]

 [/#if]
}
