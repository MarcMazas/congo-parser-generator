package org.congocc.output.java;

import java.util.*;
import org.congocc.parser.*;
import org.congocc.parser.tree.*;
import static org.congocc.parser.TokenType.*;

/**
 * A visitor that eliminates unused code.
 * It is not absolutely correct, in the sense of catching all
 * unused methods or fields, but works for our purposes.
 * For example, it does not take account overloaded methods, so
 * if the method name is referenced somewhere, it is assumed to be used.
 * However, it might be a reference to a method with the same name
 * with different arguments.
 * Also variable names can be in a sense overloaded by being defined
 * in inner classes, but we don't bother about that either.
 */
class DeadCodeEliminator extends Node.Visitor {
    private Set<String> usedNames = new HashSet<>();
    private Set<Node> alreadyVisited = new HashSet<>();
    private CompilationUnit jcu;

    DeadCodeEliminator(CompilationUnit jcu) {
        this.jcu = jcu;
    }

    void stripUnused() {
        int previousUsedNamesSize = -1;
        // Visit the tree over and over until
        // nothing is added to usedNames. Then we can stop.
        while (usedNames.size() > previousUsedNamesSize) {
            previousUsedNamesSize = usedNames.size();
            visit(jcu);
        }
        // If the name of the method is not in usedNames, we delete it.
        for (MethodDeclaration md : jcu.descendants(MethodDeclaration.class, md->!usedNames.contains(md.getName()))) {
            md.getParent().removeChild(md);
        }
        // We go through all the private FieldDeclarations and get rid of any variables that
        // are not in usedNames
        for (FieldDeclaration fd : jcu.descendants(FieldDeclaration.class, fd->isPrivate(fd))) {
            stripUnusedVars(fd);
        }

        // Add interface extends list to used names
        for (InterfaceDeclaration iface : jcu.descendants(InterfaceDeclaration.class)) {
            ExtendsList el = iface.firstDescendantOfType(ExtendsList.class);
            if (null != el) for (Identifier id : el.descendantsOfType(Identifier.class))
                usedNames.add(id.getImage());
        }

        // With the remaining field declarations, we add any type names to usedNames
        // so that we don't remove imports that refer to them.
        for (FieldDeclaration fd : jcu.descendants(FieldDeclaration.class)) {
            for (Identifier id : fd.descendantsOfType(Identifier.class)) {
        // In Foo.Bar.Baz it is only the Foo
        // that needs to be added to usedNames, for example.
                if (id.getPrevious().getType() != DOT) {
                   usedNames.add(id.getImage());
                }
            }
        }

        // Now get rid of unused imports.
        for (ImportDeclaration imp : jcu.childrenOfType(ImportDeclaration.class)) {
            if (imp.firstChildOfType(STAR) == null) {
                List<Identifier> names = imp.descendantsOfType(Identifier.class);
                Identifier name = names.get(names.size()-1);
                if (!usedNames.contains(name.getImage())) {
                    jcu.removeChild(imp);
                    //System.out.println("Removing: " + imp.getAsString());
                }
            }
        }
    }

    private boolean isPrivate(Node node) {
        if (node.firstChildOfType(PRIVATE) != null) return true;
        Modifiers mods = node.firstChildOfType(Modifiers.class);
        return mods == null ? false : mods.firstChildOfType(PRIVATE) != null;
    }

    void visit(MethodDeclaration md) {
        if (alreadyVisited.contains(md)) return;
        if (!isPrivate(md) || usedNames.contains(md.getName())) {
            md.descendants(Identifier.class).stream().forEach(id->usedNames.add(id.getImage()));
            alreadyVisited.add(md);
        }
    }

    void visit(VariableDeclarator vd) {
        if (alreadyVisited.contains(vd)) return;
        if (!isPrivate(vd.getParent()) || usedNames.contains(vd.getName())) {
            for (Identifier id : vd.descendants(Identifier.class)) {
                usedNames.add(id.getImage());
            }
            alreadyVisited.add(vd);
        }
    }

    void visit(Initializer init) {
        if (alreadyVisited.contains(init)) return;
        for (Identifier id : init.descendants(Identifier.class)) {
            usedNames.add(id.getImage());
        }
        alreadyVisited.add(init);
    }

    void visit(ConstructorDeclaration cd) {
        if (alreadyVisited.contains(cd)) return;
        for (Identifier id : cd.descendants(Identifier.class)) {
            usedNames.add(id.getImage());
        }
        alreadyVisited.add(cd);
    }

    // Get rid of any variable declarations where the variable name
    // is not in usedNames. The only complicated case is if the field
    // has more than one variable declaration comma-separated
    private void stripUnusedVars(FieldDeclaration fd) {
        Set<Node> toBeRemoved = new HashSet<Node>();
        for (VariableDeclarator vd : fd.childrenOfType(VariableDeclarator.class)) {
            if (!usedNames.contains(vd.getName())) {
                toBeRemoved.add(vd);
                int index = fd.indexOf(vd);
                Node prev = fd.getChild(index-1);
                Node next = fd.getChild(index+1);
                if (prev instanceof Token && ((Token)prev).getType()==COMMA) {
                    toBeRemoved.add(prev);
                }
                else if (next instanceof Token && ((Token)next).getType() == COMMA) {
                    toBeRemoved.add(next);
                }
            }
        }
        for (Node n : toBeRemoved) {
            fd.removeChild(n);
        }
        if (fd.firstChildOfType(VariableDeclarator.class) == null) {
            fd.getParent().removeChild(fd);
        }
    }
}