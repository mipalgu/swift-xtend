//
//  ModelFixtures.swift
//  XtendTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// Self-authored metamodels and models for the model tests.
enum ModelFixtures {
    /// A small metamodel of entities with attributes and references.
    static let entitiesEcore = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" \
        name="entities" nsURI="http://example.org/entities" nsPrefix="entities">
          <eClassifiers xsi:type="ecore:EClass" name="Model">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="entities" upperBound="-1" eType="#//Entity" containment="true"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Entity">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="abstract" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EBoolean"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="superType" eType="#//Entity"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="features" upperBound="-1" eType="#//Feature" containment="true"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Feature" abstract="true">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="many" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EBoolean"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Attribute" eSuperTypes="#//Feature">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="type" eType="#//DataKind"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Reference" eSuperTypes="#//Feature">
            <eStructuralFeatures xsi:type="ecore:EReference" name="target" eType="#//Entity"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EEnum" name="DataKind">
            <eLiterals name="STRING"/>
            <eLiterals name="INTEGER" value="1"/>
            <eLiterals name="BOOLEAN" value="2"/>
          </eClassifiers>
        </ecore:EPackage>
        """

    /// A small relational metamodel, the target of the model-to-model transformation.
    static let relationalEcore = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" \
        name="relational" nsURI="http://example.org/relational" nsPrefix="relational">
          <eClassifiers xsi:type="ecore:EClass" name="Schema">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="tables" upperBound="-1" eType="#//Table" containment="true"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Table">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="columns" upperBound="-1" eType="#//Column" containment="true"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Column">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="name" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="sqlType" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="width" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EInt"/>
            <eStructuralFeatures xsi:type="ecore:EReference" name="references" eType="#//Table"/>
          </eClassifiers>
        </ecore:EPackage>
        """

    /// A shop model with an abstract entity, attributes and a many-valued reference.
    static let shopModel = """
        <?xml version="1.0" encoding="UTF-8"?>
        <entities:Model xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:entities="http://example.org/entities" name="shop">
          <entities name="Party" abstract="true">
            <features xsi:type="entities:Attribute" name="name" type="STRING"/>
          </entities>
          <entities name="Customer" superType="//@entities.0">
            <features xsi:type="entities:Attribute" name="loyaltyPoints" type="INTEGER"/>
            <features xsi:type="entities:Reference" name="orders" many="true" target="//@entities.2"/>
          </entities>
          <entities name="Order">
            <features xsi:type="entities:Attribute" name="Number" type="INTEGER"/>
            <features xsi:type="entities:Attribute" name="express" type="BOOLEAN"/>
            <features xsi:type="entities:Reference" name="customer" target="//@entities.1"/>
          </entities>
        </entities:Model>
        """

    /// Loaded metamodels and the shop model.
    struct Loaded {
        /// The resource set holding everything.
        let resourceSet: ResourceSet
        /// The entities metamodel.
        let entities: EPackage
        /// The resource holding the entities metamodel.
        let entitiesResource: Resource
        /// The relational metamodel.
        let relational: EPackage
        /// The resource holding the shop model.
        let shop: Resource
    }

    /// Loads the fixtures into a new resource set.
    static func load() async throws -> Loaded {
        let resourceSet = ResourceSet()
        let entities = try await ModelIO.load(
            data: Data(entitiesEcore.utf8), uri: "test:/entities.ecore", format: .ecore, resourceSet: resourceSet)
        let relational = try await ModelIO.load(
            data: Data(relationalEcore.utf8), uri: "test:/relational.ecore", format: .ecore, resourceSet: resourceSet)
        let shop = try await ModelIO.load(data: Data(shopModel.utf8), uri: "test:/shop.xmi", format: .xmi, resourceSet: resourceSet)
        guard let entitiesPackage = entities.packages.first, let relationalPackage = relational.packages.first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Loaded(
            resourceSet: resourceSet, entities: entitiesPackage, entitiesResource: entities.resource,
            relational: relationalPackage, shop: shop.resource)
    }
}
