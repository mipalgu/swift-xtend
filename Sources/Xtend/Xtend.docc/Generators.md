# Generators and Transformations

Write files from models and build models from models.

## Overview

A generator is a class with a method named `doGenerate` or `generate` that takes the input
resource and a file system access, optionally followed by a generator context. This is the
shape of an Xtext `AbstractGenerator`, which a generator class may extend:

```xtend
import entities.Entity
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.generator.AbstractGenerator
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext

class SwiftGenerator extends AbstractGenerator {
    override void doGenerate(Resource resource, IFileSystemAccess2 fsa, IGeneratorContext context) {
        for (entity : resource.allContents.toIterable.filter(Entity)) {
            fsa.generateFile(entity.name + '.swift', entity.compile)
        }
    }

    def compile(Entity e) '''
        public final class «e.name» {
        }
    '''
}
```

Run it with ``XtendInterpreter/generate(resource:fileSystem:className:)``. The context is
passed as `null`. `generateFile` takes a relative path and the contents, optionally with the
name of an output configuration between them. ``XtendInMemoryFileSystemAccess`` keeps the files
in memory, and ``XtendDirectoryFileSystemAccess`` writes them below output directories.

## Model-to-model transformations

Transformations create objects with `new` for classes of a registered metamodel. The objects
are added to the interpreter's ``XtendInterpreter/targetResource``, and assigning them to a
containment feature makes them contained rather than root objects. Create methods make sure
that each source element maps to exactly one target element, even when references are
resolved before the element itself is transformed:

```xtend
def create new Table toTable(Entity e) {
    name = e.name.toUpperCase
    columns += e.features.map[column]
}

def dispatch Column column(Attribute a) {
    new Column => [ name = a.name ]
}

def dispatch Column column(Reference r) {
    new Column => [ name = r.name + '_id'; references = r.target.toTable ]
}
```

Call an entry method with ``XtendInterpreter/call(_:of:arguments:)``, passing model objects as
``XtendHostValue/object(_:_:)``.

## Metamodels as input

A resource that holds an Ecore metamodel can be the input of a generator. Its packages,
classes, attributes, references and enumerations expose the features of the Ecore metamodel,
so `c.name`, `c.abstract`, `c.ESuperTypes` and `c.EAllStructuralFeatures` work as in Java.
